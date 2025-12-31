/**
 * @description Batch class for processing scheduled recurring payments.
 * Runs daily to process invoices with Auto_Pay enabled and due dates.
 */
public class RecurringPaymentBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private Integer successCount = 0;
    private Integer failureCount = 0;
    private List<String> errorMessages = new List<String>();
    private Date processingDate;
    
    public RecurringPaymentBatch() {
        this.processingDate = Date.today();
    }
    
    public RecurringPaymentBatch(Date processDate) {
        this.processingDate = processDate;
    }
    
    /**
     * @description Query for invoices eligible for automatic payment
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Get max retry attempts from settings
        Integer maxRetries = getMaxRetryAttempts();
        
        return Database.getQueryLocator([
            SELECT Id, Name, pymtTest__Account__c, pymtTest__Total_Amount__c, pymtTest__Balance_Due__c,
                   pymtTest__Due_Date__c, pymtTest__Scheduled_Payment_Date__c, pymtTest__Auto_Pay__c,
                   pymtTest__Payment_Gateway__c, pymtTest__Retry_Count__c, pymtTest__Status__c,
                   pymtTest__Account__r.Name
            FROM pymtTest__Invoice__c
            WHERE pymtTest__Auto_Pay__c = true
            AND pymtTest__Status__c IN ('Scheduled', 'Pending', 'Failed')
            AND pymtTest__Balance_Due__c > 0
            AND pymtTest__Scheduled_Payment_Date__c <= :processingDate
            AND pymtTest__Retry_Count__c < :maxRetries
            ORDER BY pymtTest__Scheduled_Payment_Date__c ASC
        ]);
    }
    
    /**
     * @description Process each batch of invoices
     */
    public void execute(Database.BatchableContext bc, List<pymtTest__Invoice__c> invoices) {
        for (pymtTest__Invoice__c invoice : invoices) {
            try {
                processInvoicePayment(invoice);
            } catch (Exception e) {
                handlePaymentError(invoice, e.getMessage());
            }
        }
    }
    
    /**
     * @description Process payment for a single invoice
     */
    private void processInvoicePayment(pymtTest__Invoice__c invoice) {
        // Get primary payment method for the account
        pymtTest__Payment_Method__c paymentMethod = getPrimaryPaymentMethod(invoice.pymtTest__Account__c);
        
        if (paymentMethod == null) {
            handleNoPaymentMethod(invoice);
            return;
        }
        
        // Check if payment method is expired
        if (paymentMethod.pymtTest__Is_Expired__c) {
            handleExpiredPaymentMethod(invoice, paymentMethod);
            return;
        }
        
        // Determine which gateway to use (invoice gateway or payment method gateway)
        Id gatewayId = invoice.pymtTest__Payment_Gateway__c != null ? 
                       invoice.pymtTest__Payment_Gateway__c : 
                       paymentMethod.pymtTest__Payment_Gateway__c;
        
        // Build payment data
        PaymentService.PaymentData paymentData = new PaymentService.PaymentData();
        paymentData.amount = invoice.pymtTest__Balance_Due__c;
        paymentData.currencyCode = 'USD';
        paymentData.accountId = invoice.pymtTest__Account__c;
        paymentData.gatewayId = gatewayId;
        paymentData.paymentMethodId = paymentMethod.Id;
        paymentData.paymentMethodToken = paymentMethod.pymtTest__Gateway_Token__c;
        paymentData.idempotencyKey = 'AUTO-' + invoice.Id + '-' + String.valueOf(Date.today());
        
        // Set up allocation for full payment
        PaymentService.InvoiceAllocation allocation = new PaymentService.InvoiceAllocation();
        allocation.invoiceId = invoice.Id;
        allocation.amount = invoice.pymtTest__Balance_Due__c;
        allocation.isFullPayment = true;
        paymentData.invoiceAllocations = new List<PaymentService.InvoiceAllocation>{ allocation };
        
        // Process payment
        PaymentService.PaymentResult result = PaymentService.processPayment(paymentData);
        
        if (result.success) {
            handlePaymentSuccess(invoice, result);
        } else {
            handlePaymentFailure(invoice, result.message);
        }
    }
    
    /**
     * @description Get primary payment method for account
     */
    private pymtTest__Payment_Method__c getPrimaryPaymentMethod(Id accountId) {
        List<pymtTest__Payment_Method__c> methods = [
            SELECT Id, pymtTest__Gateway_Token__c, pymtTest__Payment_Gateway__c,
                   pymtTest__Is_Expired__c, pymtTest__Card_Brand__c, pymtTest__Last_Four__c
            FROM pymtTest__Payment_Method__c
            WHERE pymtTest__Account__c = :accountId
            AND pymtTest__Active__c = true
            AND pymtTest__Is_Expired__c = false
            ORDER BY pymtTest__Is_Primary__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        
        return methods.isEmpty() ? null : methods[0];
    }
    
    /**
     * @description Handle successful payment
     */
    private void handlePaymentSuccess(pymtTest__Invoice__c invoice, PaymentService.PaymentResult result) {
        successCount++;
        
        // Reset retry count
        invoice.pymtTest__Retry_Count__c = 0;
        update invoice;
        
        // Create retry log entry for success
        createRetryLog(invoice.Id, 'Success', 'Payment processed successfully', result.transactionId);
        
        // Send success notification
        sendPaymentNotification(invoice, 'SUCCESS', null);
    }
    
    /**
     * @description Handle payment failure
     */
    private void handlePaymentFailure(pymtTest__Invoice__c invoice, String errorMessage) {
        failureCount++;
        errorMessages.add(invoice.Name + ': ' + errorMessage);
        
        // Increment retry count
        invoice.pymtTest__Retry_Count__c = (invoice.pymtTest__Retry_Count__c == null ? 0 : invoice.pymtTest__Retry_Count__c) + 1;
        invoice.pymtTest__Status__c = 'Failed';
        
        // Schedule next retry if under max attempts
        Integer maxRetries = getMaxRetryAttempts();
        if (invoice.pymtTest__Retry_Count__c < maxRetries) {
            invoice.pymtTest__Scheduled_Payment_Date__c = getNextRetryDate(invoice.pymtTest__Retry_Count__c.intValue());
        }
        
        update invoice;
        
        // Create retry log entry
        createRetryLog(invoice.Id, 'Failed', errorMessage, null);
        
        // Send failure notification
        sendPaymentNotification(invoice, 'FAILED', errorMessage);
    }
    
    /**
     * @description Handle payment error (exception)
     */
    private void handlePaymentError(pymtTest__Invoice__c invoice, String errorMessage) {
        failureCount++;
        errorMessages.add(invoice.Name + ': System error - ' + errorMessage);
        
        invoice.pymtTest__Retry_Count__c = (invoice.pymtTest__Retry_Count__c == null ? 0 : invoice.pymtTest__Retry_Count__c) + 1;
        invoice.pymtTest__Status__c = 'Failed';
        update invoice;
        
        createRetryLog(invoice.Id, 'Error', errorMessage, null);
    }
    
    /**
     * @description Handle no payment method on file
     */
    private void handleNoPaymentMethod(pymtTest__Invoice__c invoice) {
        failureCount++;
        String message = 'No active payment method on file';
        errorMessages.add(invoice.Name + ': ' + message);
        
        invoice.pymtTest__Status__c = 'Failed';
        update invoice;
        
        createRetryLog(invoice.Id, 'Failed', message, null);
        sendPaymentNotification(invoice, 'NO_PAYMENT_METHOD', message);
    }
    
    /**
     * @description Handle expired payment method
     */
    private void handleExpiredPaymentMethod(pymtTest__Invoice__c invoice, pymtTest__Payment_Method__c pm) {
        failureCount++;
        String message = 'Payment method expired (' + pm.pymtTest__Card_Brand__c + ' ****' + pm.pymtTest__Last_Four__c + ')';
        errorMessages.add(invoice.Name + ': ' + message);
        
        invoice.pymtTest__Status__c = 'Failed';
        update invoice;
        
        createRetryLog(invoice.Id, 'Failed', message, null);
        sendPaymentNotification(invoice, 'EXPIRED_CARD', message);
    }
    
    /**
     * @description Create a retry log entry
     */
    private void createRetryLog(Id invoiceId, String status, String message, Id transactionId) {
        pymtTest__Retry_Log__c log = new pymtTest__Retry_Log__c(
            pymtTest__Invoice__c = invoiceId,
            pymtTest__Status__c = status,
            pymtTest__Message__c = message,
            pymtTest__Transaction__c = transactionId,
            pymtTest__Attempt_Date__c = DateTime.now()
        );
        insert log;
    }
    
    /**
     * @description Send payment notification
     */
    private void sendPaymentNotification(pymtTest__Invoice__c invoice, String notificationType, String message) {
        // Create bell notification
        Set<String> recipientIds = getNotificationRecipients(invoice);
        
        if (!recipientIds.isEmpty()) {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(getNotificationTitle(notificationType));
            notification.setBody(getNotificationBody(invoice, notificationType, message));
            notification.setNotificationTypeId(getCustomNotificationTypeId());
            notification.setTargetId(invoice.Id);
            
            try {
                notification.send(recipientIds);
            } catch (Exception e) {
                System.debug('Failed to send notification: ' + e.getMessage());
            }
        }
    }
    
    private Set<String> getNotificationRecipients(pymtTest__Invoice__c invoice) {
        // Get account owner and payment admin users
        Set<String> recipients = new Set<String>();
        
        // Add current user as fallback
        recipients.add(UserInfo.getUserId());
        
        return recipients;
    }
    
    private String getNotificationTitle(String type) {
        Map<String, String> titles = new Map<String, String>{
            'SUCCESS' => 'Payment Successful',
            'FAILED' => 'Payment Failed',
            'NO_PAYMENT_METHOD' => 'Payment Method Required',
            'EXPIRED_CARD' => 'Card Expired'
        };
        return titles.containsKey(type) ? titles.get(type) : 'Payment Update';
    }
    
    private String getNotificationBody(pymtTest__Invoice__c invoice, String type, String message) {
        if (type == 'SUCCESS') {
            return 'Payment for ' + invoice.Name + ' was processed successfully.';
        }
        return 'Payment for ' + invoice.Name + ' failed: ' + message;
    }
    
    private Id getCustomNotificationTypeId() {
        // Query for custom notification type - create if doesn't exist
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType 
            WHERE DeveloperName = 'Payment_Notification' LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
    
    /**
     * @description Get next retry date based on attempt number
     */
    private Date getNextRetryDate(Integer attemptNumber) {
        // Exponential backoff: 1 day, 2 days, 4 days, etc.
        Integer daysToAdd = (Integer) Math.pow(2, attemptNumber - 1);
        return Date.today().addDays(daysToAdd);
    }
    
    /**
     * @description Get max retry attempts from settings
     */
    private Integer getMaxRetryAttempts() {
        // Default to 3, can be overridden by custom setting
        pymtTest__Payment_Settings__c settings = pymtTest__Payment_Settings__c.getOrgDefaults();
        return settings != null && settings.pymtTest__Max_Retry_Attempts__c != null ? 
               settings.pymtTest__Max_Retry_Attempts__c.intValue() : 3;
    }
    
    /**
     * @description Finish method - send summary notification
     */
    public void finish(Database.BatchableContext bc) {
        // Send summary notification
        String subject = 'Recurring Payment Processing Complete';
        String body = 'Processed: ' + (successCount + failureCount) + ' invoices\n' +
                     'Successful: ' + successCount + '\n' +
                     'Failed: ' + failureCount;
        
        if (!errorMessages.isEmpty()) {
            body += '\n\nErrors:\n' + String.join(errorMessages, '\n');
        }
        
        // Log results
        System.debug(body);
        
        // Optionally send email to admins
        // sendSummaryEmail(subject, body);
    }
}
