/**
 * @description Main service class for payment operations.
 * Handles payment processing, allocations, refunds, and payment method management.
 */
public with sharing class PaymentService {

    private static PaymentResult paymentSuccess(Id txnId, String gatewayTxnId) {
        PaymentResult r = new PaymentResult();
        r.success = true;
        r.transactionId = txnId;
        r.gatewayTransactionId = gatewayTxnId;
        r.message = 'Payment processed successfully';
        return r;
    }

    private static PaymentResult paymentFailure(String message) {
        PaymentResult r = new PaymentResult();
        r.success = false;
        r.message = message;
        return r;
    }
    
    /**
     * @description Process a payment for one or more invoices
     * @param paymentData The payment data including invoices and allocations
     * @return PaymentResult The result of the payment operation
     */
    @AuraEnabled
    public static PaymentResult processPayment(PaymentData paymentData) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Validate payment data
            List<String> validationErrors = validatePaymentData(paymentData);
            if (!validationErrors.isEmpty()) {
                return paymentFailure(String.join(validationErrors, '; '));
            }
            
            // Get the gateway
            PaymentGateway gateway = getGatewayForPayment(paymentData);
            
            // Build payment request
            PaymentRequest request = buildPaymentRequest(paymentData);
            
            // Process the payment
            PaymentResponse response = gateway.sale(request);
            
            if (response.success) {
                // Create transaction record
                pymts__Transaction__c txn = createTransactionRecord(paymentData, response);
                
                // Create payment allocations
                List<pymts__Payment_Allocation__c> allocations = createPaymentAllocations(
                    txn.Id, paymentData.invoiceAllocations
                );
                
                // Update invoice amounts
                updateInvoiceAmounts(paymentData.invoiceAllocations);
                
                // Handle overpayment (create account credit)
                Decimal totalAllocated = getTotalAllocated(paymentData.invoiceAllocations);
                if (paymentData.amount > totalAllocated) {
                    createAccountCredit(paymentData.accountId, txn.Id, 
                                       paymentData.amount - totalAllocated);
                }
                
                // Save payment method if requested
                if (paymentData.savePaymentMethod && String.isNotBlank(response.paymentMethodToken)) {
                    savePaymentMethod(paymentData, response);
                }
                
                // Create audit log
                createAuditLog('Payment Processed', txn.Id, paymentData.accountId, 
                              'Payment of ' + paymentData.amount + ' processed successfully');
                
                return paymentSuccess(txn.Id, response.transactionId);
                
            } else {
                // Payment failed
                createAuditLog('Payment Failed', null, paymentData.accountId, 
                              response.errorMessage);
                
                return paymentFailure(response.errorMessage);
            }
            
        } catch (Exception e) {
            Database.rollback(sp);
            createAuditLog('Payment Error', null, paymentData.accountId, e.getMessage());
            return paymentFailure('Payment processing error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Process a refund for a transaction
     * @param transactionId The Salesforce transaction ID
     * @param amount The amount to refund (null for full refund)
     * @return PaymentResult The result
     */
    @AuraEnabled
    public static PaymentResult processRefund(Id transactionId, Decimal amount) {
        try {
            pymts__Transaction__c originalTxn = [
                SELECT Id, pymts__Amount__c, pymts__Gateway_Transaction_Id__c,
                       pymts__Payment_Gateway__c, pymts__Account__c, pymts__Status__c
                FROM pymts__Transaction__c
                WHERE Id = :transactionId
                LIMIT 1
            ];
            
            if (originalTxn.pymts__Status__c == 'Refunded') {
                return paymentFailure('Transaction has already been fully refunded');
            }
            
            Decimal refundAmount = amount != null ? amount : originalTxn.pymts__Amount__c;
            
            PaymentGateway gateway = GatewayFactory.getGateway(originalTxn.pymts__Payment_Gateway__c);
            PaymentResponse response = gateway.refund(originalTxn.pymts__Gateway_Transaction_Id__c, refundAmount);
            
            if (response.success) {
                // Create refund transaction record
                pymts__Transaction__c refundTxn = new pymts__Transaction__c(
                    pymts__Type__c = 'Refund',
                    pymts__Amount__c = refundAmount,
                    pymts__Status__c = 'Approved',
                    pymts__Gateway_Transaction_Id__c = response.transactionId,
                    pymts__Payment_Gateway__c = originalTxn.pymts__Payment_Gateway__c,
                    pymts__Account__c = originalTxn.pymts__Account__c,
                    pymts__Response_Message__c = response.rawResponse
                );
                insert refundTxn;
                
                // Update original transaction status
                if (refundAmount >= originalTxn.pymts__Amount__c) {
                    originalTxn.pymts__Status__c = 'Refunded';
                } else {
                    originalTxn.pymts__Status__c = 'Partially Refunded';
                }
                update originalTxn;
                
                // Update invoice allocations and amounts
                reverseAllocations(transactionId, refundAmount);
                
                createAuditLog('Refund Processed', refundTxn.Id, originalTxn.pymts__Account__c,
                              'Refund of ' + refundAmount + ' processed');
                
                return paymentSuccess(refundTxn.Id, response.transactionId);
            } else {
                return paymentFailure(response.errorMessage);
            }
            
        } catch (Exception e) {
            return paymentFailure('Refund error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Void a transaction
     * @param transactionId The Salesforce transaction ID
     * @return PaymentResult The result
     */
    @AuraEnabled
    public static PaymentResult voidTransaction(Id transactionId) {
        try {
            pymts__Transaction__c txn = [
                SELECT Id, pymts__Amount__c, pymts__Gateway_Transaction_Id__c,
                       pymts__Payment_Gateway__c, pymts__Account__c, pymts__Status__c
                FROM pymts__Transaction__c
                WHERE Id = :transactionId
                LIMIT 1
            ];
            
            if (txn.pymts__Status__c != 'Approved' && txn.pymts__Status__c != 'Pending') {
                return paymentFailure('Transaction cannot be voided in current status');
            }
            
            PaymentGateway gateway = GatewayFactory.getGateway(txn.pymts__Payment_Gateway__c);
            PaymentResponse response = gateway.voidTransaction(txn.pymts__Gateway_Transaction_Id__c);
            
            if (response.success) {
                txn.pymts__Status__c = 'Voided';
                update txn;
                
                // Reverse allocations
                reverseAllocations(transactionId, txn.pymts__Amount__c);
                
                createAuditLog('Transaction Voided', txn.Id, txn.pymts__Account__c,
                              'Transaction voided');
                
                return paymentSuccess(txn.Id, response.transactionId);
            } else {
                return paymentFailure(response.errorMessage);
            }
            
        } catch (Exception e) {
            return paymentFailure('Void error: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get open invoices for an account
     * @param accountId The account ID
     * @return List<InvoiceWrapper> List of open invoices
     */
    @AuraEnabled(cacheable=true)
    public static List<InvoiceWrapper> getOpenInvoices(Id accountId) {
        List<InvoiceWrapper> wrappers = new List<InvoiceWrapper>();
        
        List<pymts__Invoice__c> invoices = [
            SELECT Id, Name, pymts__Total_Amount__c, pymts__Amount_Paid__c,
                   pymts__Balance_Due__c, pymts__Due_Date__c, pymts__Status__c,
                   pymts__Order__c, pymts__Order__r.OrderNumber,
                   pymts__Payment_Gateway__c, pymts__Payment_Gateway__r.Name
            FROM pymts__Invoice__c
            WHERE pymts__Account__c = :accountId
            AND pymts__Balance_Due__c > 0
            AND pymts__Status__c NOT IN ('Cancelled', 'Paid')
            ORDER BY pymts__Due_Date__c ASC
        ];
        
        for (pymts__Invoice__c inv : invoices) {
            wrappers.add(new InvoiceWrapper(inv));
        }
        
        return wrappers;
    }
    
    /**
     * @description Get payment methods for an account
     * @param accountId The account ID
     * @return List<PaymentMethodWrapper> List of payment methods
     */
    @AuraEnabled(cacheable=true)
    public static List<PaymentMethodWrapper> getPaymentMethods(Id accountId) {
        List<PaymentMethodWrapper> wrappers = new List<PaymentMethodWrapper>();
        
        List<pymts__Payment_Method__c> methods = [
            SELECT Id, Name, pymts__Type__c, pymts__Card_Brand__c, pymts__Last_Four__c,
                   pymts__Expiration_Month__c, pymts__Expiration_Year__c, pymts__Active__c,
                   pymts__Is_Primary__c, pymts__Is_Expired__c, pymts__Payment_Gateway__c,
                   pymts__Payment_Gateway__r.Name, pymts__Payment_Gateway__r.pymts__Gateway_Type__c
            FROM pymts__Payment_Method__c
            WHERE pymts__Account__c = :accountId
            AND pymts__Active__c = true
            ORDER BY pymts__Is_Primary__c DESC, CreatedDate DESC
        ];
        
        for (pymts__Payment_Method__c pm : methods) {
            wrappers.add(new PaymentMethodWrapper(pm));
        }
        
        return wrappers;
    }
    
    /**
     * @description Add a new payment method
     * @param accountId The account ID
     * @param gatewayId The gateway ID
     * @param token The payment method token from client-side tokenization
     * @param cardDetails Card details (brand, last4, exp)
     * @param setAsPrimary Whether to set as primary
     * @return Id The new payment method ID
     */
    @AuraEnabled
    public static Id addPaymentMethod(Id accountId, Id gatewayId, String token, 
                                      Map<String, Object> cardDetails, Boolean setAsPrimary) {
        try {
            // If setting as primary, unset other primary methods
            if (setAsPrimary) {
                List<pymts__Payment_Method__c> existingPrimary = [
                    SELECT Id, pymts__Is_Primary__c
                    FROM pymts__Payment_Method__c
                    WHERE pymts__Account__c = :accountId AND pymts__Is_Primary__c = true
                ];
                for (pymts__Payment_Method__c pm : existingPrimary) {
                    pm.pymts__Is_Primary__c = false;
                }
                update existingPrimary;
            }
            
            pymts__Payment_Method__c newMethod = new pymts__Payment_Method__c(
                pymts__Account__c = accountId,
                pymts__Payment_Gateway__c = gatewayId,
                pymts__Gateway_Token__c = token,
                pymts__Type__c = 'Credit Card',
                pymts__Card_Brand__c = (String) cardDetails.get('brand'),
                pymts__Last_Four__c = (String) cardDetails.get('last4'),
                pymts__Expiration_Month__c = (Integer) cardDetails.get('expMonth'),
                pymts__Expiration_Year__c = (Integer) cardDetails.get('expYear'),
                pymts__Active__c = true,
                pymts__Is_Primary__c = setAsPrimary
            );
            
            insert newMethod;
            
            createAuditLog('Payment Method Added', null, accountId,
                          'New payment method added: ' + newMethod.pymts__Card_Brand__c + 
                          ' ending in ' + newMethod.pymts__Last_Four__c);
            
            return newMethod.Id;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error adding payment method: ' + e.getMessage());
        }
    }
    
    /**
     * @description Set a payment method as primary
     * @param paymentMethodId The payment method ID
     */
    @AuraEnabled
    public static void setPrimaryPaymentMethod(Id paymentMethodId) {
        try {
            pymts__Payment_Method__c method = [
                SELECT Id, pymts__Account__c, pymts__Is_Primary__c
                FROM pymts__Payment_Method__c
                WHERE Id = :paymentMethodId
            ];
            
            // Unset other primary methods for this account
            List<pymts__Payment_Method__c> existingPrimary = [
                SELECT Id, pymts__Is_Primary__c
                FROM pymts__Payment_Method__c
                WHERE pymts__Account__c = :method.pymts__Account__c 
                AND pymts__Is_Primary__c = true
                AND Id != :paymentMethodId
            ];
            for (pymts__Payment_Method__c pm : existingPrimary) {
                pm.pymts__Is_Primary__c = false;
            }
            update existingPrimary;
            
            method.pymts__Is_Primary__c = true;
            update method;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error setting primary payment method: ' + e.getMessage());
        }
    }
    
    /**
     * @description Deactivate a payment method
     * @param paymentMethodId The payment method ID
     */
    @AuraEnabled
    public static void deactivatePaymentMethod(Id paymentMethodId) {
        try {
            pymts__Payment_Method__c method = [
                SELECT Id, pymts__Active__c
                FROM pymts__Payment_Method__c
                WHERE Id = :paymentMethodId
            ];
            method.pymts__Active__c = false;
            update method;
        } catch (Exception e) {
            throw new AuraHandledException('Error deactivating payment method: ' + e.getMessage());
        }
    }
    
    /**
     * @description Apply account credit to an invoice
     * @param creditId The account credit ID
     * @param invoiceId The invoice ID
     * @param amount The amount to apply
     */
    @AuraEnabled
    public static void applyCredit(Id creditId, Id invoiceId, Decimal amount) {
        try {
            pymts__Account_Credit__c credit = [
                SELECT Id, pymts__Remaining_Balance__c
                FROM pymts__Account_Credit__c
                WHERE Id = :creditId
            ];
            
            if (credit.pymts__Remaining_Balance__c < amount) {
                throw new AuraHandledException('Insufficient credit balance');
            }
            
            pymts__Invoice__c invoice = [
                SELECT Id, pymts__Amount_Paid__c, pymts__Balance_Due__c
                FROM pymts__Invoice__c
                WHERE Id = :invoiceId
            ];
            
            if (amount > invoice.pymts__Balance_Due__c) {
                throw new AuraHandledException('Amount exceeds invoice balance');
            }
            
            // Update credit
            credit.pymts__Remaining_Balance__c -= amount;
            update credit;
            
            // Update invoice
            invoice.pymts__Amount_Paid__c += amount;
            updateInvoiceStatus(invoice);
            update invoice;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error applying credit: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get active payment gateways
     * @return List<pymts__Payment_Gateway__c> List of active gateways
     */
    @AuraEnabled(cacheable=true)
    public static List<pymts__Payment_Gateway__c> getActiveGateways() {
        return [
            SELECT Id, Name, pymts__Gateway_Type__c, pymts__Environment__c,
                   pymts__Is_Default__c, pymts__Active__c
            FROM pymts__Payment_Gateway__c
            WHERE pymts__Active__c = true
            ORDER BY pymts__Is_Default__c DESC, Name ASC
        ];
    }
    
    /**
     * @description Get gateway configuration details
     * @param gatewayId The gateway ID
     * @return Map<String, Object> Gateway configuration
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getGatewayConfiguration(Id gatewayId) {
        pymts__Payment_Gateway__c gateway = [
            SELECT Id, Name, pymts__Gateway_Type__c, pymts__Environment__c,
                   pymts__Public_Key__c, pymts__Active__c, pymts__Is_Default__c
            FROM pymts__Payment_Gateway__c
            WHERE Id = :gatewayId
        ];
        
        Map<String, Object> config = new Map<String, Object>();
        config.put('id', gateway.Id);
        config.put('name', gateway.Name);
        config.put('type', gateway.pymts__Gateway_Type__c);
        config.put('environment', gateway.pymts__Environment__c);
        config.put('publicKey', gateway.pymts__Public_Key__c);
        config.put('isActive', gateway.pymts__Active__c);
        config.put('isDefault', gateway.pymts__Is_Default__c);
        
        return config;
    }
    
    /**
     * @description Remove (deactivate) a payment method
     * @param paymentMethodId The payment method ID
     */
    @AuraEnabled
    public static void removePaymentMethod(Id paymentMethodId) {
        deactivatePaymentMethod(paymentMethodId);
    }
    
    /**
     * @description Get account credits for an account
     * @param accountId The account ID
     * @return List<pymts__Account_Credit__c> List of credits with remaining balance
     */
    @AuraEnabled(cacheable=true)
    public static List<pymts__Account_Credit__c> getAccountCredits(Id accountId) {
        return getAvailableCredits(accountId);
    }
    
    /**
     * @description Get available credits for an account
     * @param accountId The account ID
     * @return List<pymts__Account_Credit__c> List of credits with remaining balance
     */
    @AuraEnabled(cacheable=true)
    public static List<pymts__Account_Credit__c> getAvailableCredits(Id accountId) {
        return [
            SELECT Id, Name, pymts__Original_Amount__c, pymts__Remaining_Balance__c,
                   CreatedDate
            FROM pymts__Account_Credit__c
            WHERE pymts__Account__c = :accountId
            AND pymts__Remaining_Balance__c > 0
            ORDER BY CreatedDate ASC
        ];
    }
    
    // ========== Private Helper Methods ==========
    
    private static List<String> validatePaymentData(PaymentData data) {
        List<String> errors = new List<String>();
        
        if (data.amount == null || data.amount <= 0) {
            errors.add('Payment amount must be greater than zero');
        }
        
        if (data.accountId == null) {
            errors.add('Account is required');
        }
        
        if (String.isBlank(data.paymentMethodToken) && String.isBlank(data.cardToken)) {
            errors.add('Payment method or card token is required');
        }
        
        if (data.invoiceAllocations == null || data.invoiceAllocations.isEmpty()) {
            errors.add('At least one invoice allocation is required');
        }
        
        return errors;
    }
    
    private static PaymentGateway getGatewayForPayment(PaymentData data) {
        if (data.gatewayId != null) {
            return GatewayFactory.getGateway(data.gatewayId);
        }
        return GatewayFactory.getDefaultGateway();
    }
    
    private static PaymentRequest buildPaymentRequest(PaymentData data) {
        PaymentRequest request = new PaymentRequest();
        request.amount = data.amount;
        request.currency_x = data.currencyCode != null ? data.currencyCode : 'USD';
        request.paymentMethodToken = data.paymentMethodToken;
        request.cardToken = data.cardToken;
        request.accountId = data.accountId;
        request.idempotencyKey = data.idempotencyKey;
        request.description = 'Payment for invoices';
        request.savePaymentMethod = data.savePaymentMethod;
        request.setAsPrimary = data.setAsPrimary;
        
        return request;
    }
    
    private static pymts__Transaction__c createTransactionRecord(PaymentData data, PaymentResponse response) {
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Type__c = 'Sale',
            pymts__Amount__c = data.amount,
            pymts__Status__c = response.status == 'Approved' ? 'Approved' : 'Declined',
            pymts__Gateway_Transaction_Id__c = response.transactionId,
            pymts__Payment_Gateway__c = data.gatewayId,
            pymts__Account__c = data.accountId,
            pymts__Payment_Method__c = data.paymentMethodId,
            pymts__Response_Message__c = response.rawResponse,
            pymts__Idempotency_Key__c = data.idempotencyKey
        );
        insert txn;
        return txn;
    }
    
    private static List<pymts__Payment_Allocation__c> createPaymentAllocations(
        Id transactionId, List<InvoiceAllocation> allocations
    ) {
        List<pymts__Payment_Allocation__c> records = new List<pymts__Payment_Allocation__c>();
        
        for (InvoiceAllocation alloc : allocations) {
            records.add(new pymts__Payment_Allocation__c(
                pymts__Transaction__c = transactionId,
                pymts__Invoice__c = alloc.invoiceId,
                pymts__Amount__c = alloc.amount
            ));
        }
        
        insert records;
        return records;
    }
    
    private static void updateInvoiceAmounts(List<InvoiceAllocation> allocations) {
        Set<Id> invoiceIds = new Set<Id>();
        Map<Id, Decimal> amountsByInvoice = new Map<Id, Decimal>();
        
        for (InvoiceAllocation alloc : allocations) {
            invoiceIds.add(alloc.invoiceId);
            if (!amountsByInvoice.containsKey(alloc.invoiceId)) {
                amountsByInvoice.put(alloc.invoiceId, 0);
            }
            amountsByInvoice.put(alloc.invoiceId, 
                amountsByInvoice.get(alloc.invoiceId) + alloc.amount);
        }
        
        List<pymts__Invoice__c> invoices = [
            SELECT Id, pymts__Amount_Paid__c, pymts__Total_Amount__c, pymts__Status__c
            FROM pymts__Invoice__c
            WHERE Id IN :invoiceIds
        ];
        
        for (pymts__Invoice__c inv : invoices) {
            inv.pymts__Amount_Paid__c += amountsByInvoice.get(inv.Id);
            updateInvoiceStatus(inv);
        }
        
        update invoices;
    }
    
    private static void updateInvoiceStatus(pymts__Invoice__c invoice) {
        Decimal balance = invoice.pymts__Total_Amount__c - invoice.pymts__Amount_Paid__c;
        
        if (balance <= 0) {
            invoice.pymts__Status__c = 'Paid';
        } else if (invoice.pymts__Amount_Paid__c > 0) {
            invoice.pymts__Status__c = 'Partially Paid';
        }
    }
    
    private static Decimal getTotalAllocated(List<InvoiceAllocation> allocations) {
        Decimal total = 0;
        for (InvoiceAllocation alloc : allocations) {
            total += alloc.amount;
        }
        return total;
    }
    
    private static void createAccountCredit(Id accountId, Id transactionId, Decimal amount) {
        pymts__Account_Credit__c credit = new pymts__Account_Credit__c(
            pymts__Account__c = accountId,
            pymts__Source_Transaction__c = transactionId,
            pymts__Original_Amount__c = amount,
            pymts__Remaining_Balance__c = amount
        );
        insert credit;
    }
    
    private static void savePaymentMethod(PaymentData data, PaymentResponse response) {
        // Check if payment method already exists
        List<pymts__Payment_Method__c> existing = [
            SELECT Id FROM pymts__Payment_Method__c
            WHERE pymts__Gateway_Token__c = :response.paymentMethodToken
            AND pymts__Account__c = :data.accountId
            LIMIT 1
        ];
        
        if (existing.isEmpty()) {
            Map<String, Object> cardDetails = new Map<String, Object>{
                'brand' => response.cardBrand,
                'last4' => response.cardLast4,
                'expMonth' => response.cardExpMonth,
                'expYear' => response.cardExpYear
            };
            
            addPaymentMethod(data.accountId, data.gatewayId, response.paymentMethodToken,
                           cardDetails, data.setAsPrimary);
        }
    }
    
    private static void reverseAllocations(Id transactionId, Decimal amount) {
        List<pymts__Payment_Allocation__c> allocations = [
            SELECT Id, pymts__Invoice__c, pymts__Amount__c
            FROM pymts__Payment_Allocation__c
            WHERE pymts__Transaction__c = :transactionId
        ];
        
        Set<Id> invoiceIds = new Set<Id>();
        Map<Id, Decimal> reverseAmounts = new Map<Id, Decimal>();
        
        for (pymts__Payment_Allocation__c alloc : allocations) {
            invoiceIds.add(alloc.pymts__Invoice__c);
            reverseAmounts.put(alloc.pymts__Invoice__c, alloc.pymts__Amount__c);
        }
        
        List<pymts__Invoice__c> invoices = [
            SELECT Id, pymts__Amount_Paid__c, pymts__Status__c
            FROM pymts__Invoice__c
            WHERE Id IN :invoiceIds
        ];
        
        for (pymts__Invoice__c inv : invoices) {
            inv.pymts__Amount_Paid__c -= reverseAmounts.get(inv.Id);
            if (inv.pymts__Amount_Paid__c < 0) {
                inv.pymts__Amount_Paid__c = 0;
            }
            inv.pymts__Status__c = inv.pymts__Amount_Paid__c > 0 ? 'Partially Paid' : 'Pending';
        }
        
        update invoices;
    }
    
    private static void createAuditLog(String action, Id transactionId, Id accountId, String details) {
        // TODO: Create audit log record
        System.debug('AUDIT: ' + action + ' - ' + details);
    }
    
    // ========== Wrapper Classes ==========
    
    public class PaymentData {
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public Id accountId { get; set; }
        @AuraEnabled public Id gatewayId { get; set; }
        @AuraEnabled public Id paymentMethodId { get; set; }
        @AuraEnabled public String paymentMethodToken { get; set; }
        @AuraEnabled public String cardToken { get; set; }
        @AuraEnabled public Boolean savePaymentMethod { get; set; }
        @AuraEnabled public Boolean setAsPrimary { get; set; }
        @AuraEnabled public String idempotencyKey { get; set; }
        @AuraEnabled public List<InvoiceAllocation> invoiceAllocations { get; set; }
    }
    
    public class InvoiceAllocation {
        @AuraEnabled public Id invoiceId { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Boolean isFullPayment { get; set; }
    }
    
    public class PaymentResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id transactionId { get; set; }
        @AuraEnabled public String gatewayTransactionId { get; set; }
    }
    
    public class InvoiceWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Decimal amountPaid { get; set; }
        @AuraEnabled public Decimal balanceDue { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String orderNumber { get; set; }
        @AuraEnabled public Id gatewayId { get; set; }
        @AuraEnabled public String gatewayName { get; set; }
        
        public InvoiceWrapper(pymts__Invoice__c inv) {
            this.id = inv.Id;
            this.name = inv.Name;
            this.totalAmount = inv.pymts__Total_Amount__c;
            this.amountPaid = inv.pymts__Amount_Paid__c;
            this.balanceDue = inv.pymts__Balance_Due__c;
            this.dueDate = inv.pymts__Due_Date__c;
            this.status = inv.pymts__Status__c;
            this.orderNumber = inv.pymts__Order__r?.OrderNumber;
            this.gatewayId = inv.pymts__Payment_Gateway__c;
            this.gatewayName = inv.pymts__Payment_Gateway__r?.Name;
        }
    }
    
    public class PaymentMethodWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String cardBrand { get; set; }
        @AuraEnabled public String lastFour { get; set; }
        @AuraEnabled public Integer expMonth { get; set; }
        @AuraEnabled public Integer expYear { get; set; }
        @AuraEnabled public Boolean isPrimary { get; set; }
        @AuraEnabled public Boolean isExpired { get; set; }
        @AuraEnabled public String gatewayName { get; set; }
        @AuraEnabled public String gatewayType { get; set; }
        @AuraEnabled public String displayName { get; set; }
        
        public PaymentMethodWrapper(pymts__Payment_Method__c pm) {
            this.id = pm.Id;
            this.name = pm.Name;
            this.type = pm.pymts__Type__c;
            this.cardBrand = pm.pymts__Card_Brand__c;
            this.lastFour = pm.pymts__Last_Four__c;
            this.expMonth = pm.pymts__Expiration_Month__c != null ? 
                           Integer.valueOf(pm.pymts__Expiration_Month__c) : null;
            this.expYear = pm.pymts__Expiration_Year__c != null ? 
                          Integer.valueOf(pm.pymts__Expiration_Year__c) : null;
            this.isPrimary = pm.pymts__Is_Primary__c;
            this.isExpired = pm.pymts__Is_Expired__c;
            this.gatewayName = pm.pymts__Payment_Gateway__r?.Name;
            this.gatewayType = pm.pymts__Payment_Gateway__r?.pymts__Gateway_Type__c;
            this.displayName = pm.pymts__Card_Brand__c + ' •••• ' + pm.pymts__Last_Four__c;
        }
    }
}
