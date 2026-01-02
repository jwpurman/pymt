/**
 * @description REST endpoint for payment gateway webhooks.
 * Handles real-time notifications for transaction settlements, returns, and disputes.
 * 
 * Endpoints:
 * POST /services/apexrest/pymt/webhook/stripe
 * POST /services/apexrest/pymt/webhook/authorizenet
 * POST /services/apexrest/pymt/webhook/braintree
 */
@RestResource(urlMapping='/pymt/webhook/*')
global with sharing class PaymentWebhookEndpoint {
    
    /**
     * @description Handle incoming webhook POST requests
     */
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Get the gateway type from the URL
            String requestUri = req.requestURI;
            String gatewayType = extractGatewayType(requestUri);
            
            String requestBody = req.requestBody.toString();
            Map<String, String> headers = req.headers;
            
            // Log incoming webhook
            logWebhook(gatewayType, requestBody, headers);
            
            // Route to appropriate handler
            WebhookResult result;
            
            switch on gatewayType.toLowerCase() {
                when 'stripe' {
                    result = handleStripeWebhook(requestBody, headers);
                }
                when 'authorizenet' {
                    result = handleAuthorizeNetWebhook(requestBody, headers);
                }
                when 'braintree' {
                    result = handleBraintreeWebhook(requestBody, headers);
                }
                when else {
                    result = new WebhookResult(false, 'Unknown gateway type: ' + gatewayType);
                }
            }
            
            if (result.success) {
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('{"status":"success"}');
            } else {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"status":"error","message":"' + result.message + '"}');
            }
            
        } catch (Exception e) {
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"status":"error","message":"' + e.getMessage() + '"}');
            System.debug('Webhook error: ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }
    
    /**
     * @description Extract gateway type from URL
     */
    private static String extractGatewayType(String requestUri) {
        // URL format: /services/apexrest/pymt/webhook/{gateway}
        List<String> parts = requestUri.split('/');
        return parts[parts.size() - 1];
    }
    
    /**
     * @description Handle Stripe webhooks
     */
    private static WebhookResult handleStripeWebhook(String body, Map<String, String> headers) {
        // Verify webhook signature
        String signature = headers.get('Stripe-Signature');
        if (!verifyStripeSignature(body, signature)) {
            return new WebhookResult(false, 'Invalid signature');
        }
        
        Map<String, Object> event = (Map<String, Object>) JSON.deserializeUntyped(body);
        String eventType = (String) event.get('type');
        Map<String, Object> data = (Map<String, Object>) event.get('data');
        Map<String, Object> eventObject = (Map<String, Object>) data.get('object');
        
        switch on eventType {
            // Payment Intent events
            when 'payment_intent.succeeded' {
                return handleStripePaymentSuccess(eventObject);
            }
            when 'payment_intent.payment_failed' {
                return handleStripePaymentFailed(eventObject);
            }
            
            // Charge events (includes ACH)
            when 'charge.succeeded' {
                return handleStripeChargeSucceeded(eventObject);
            }
            when 'charge.failed' {
                return handleStripeChargeFailed(eventObject);
            }
            when 'charge.refunded' {
                return handleStripeChargeRefunded(eventObject);
            }
            when 'charge.dispute.created' {
                return handleStripeDispute(eventObject, 'created');
            }
            when 'charge.dispute.closed' {
                return handleStripeDispute(eventObject, 'closed');
            }
            
            // ACH-specific events
            when 'payment_intent.processing' {
                return handleStripeACHProcessing(eventObject);
            }
            
            // Payment method events
            when 'payment_method.attached' {
                return new WebhookResult(true, 'Payment method attached');
            }
            when 'customer.source.expiring' {
                return handleStripeCardExpiring(eventObject);
            }
            
            when else {
                // Acknowledge but don't process unhandled events
                return new WebhookResult(true, 'Event type not handled: ' + eventType);
            }
        }
    }
    
    /**
     * @description Handle Authorize.Net webhooks (Silent Post)
     */
    private static WebhookResult handleAuthorizeNetWebhook(String body, Map<String, String> headers) {
        // Authorize.Net sends data as form-encoded or JSON depending on configuration
        Map<String, Object> data;
        
        try {
            data = (Map<String, Object>) JSON.deserializeUntyped(body);
        } catch (Exception e) {
            // Try parsing as form data
            data = parseFormData(body);
        }
        
        String eventType = (String) data.get('eventType');
        Map<String, Object> payload = (Map<String, Object>) data.get('payload');
        
        if (payload == null) {
            payload = data; // Silent Post format
        }
        
        switch on eventType {
            when 'net.authorize.payment.authcapture.created' {
                return handleAuthNetPaymentCreated(payload);
            }
            when 'net.authorize.payment.capture.created' {
                return handleAuthNetCaptureCreated(payload);
            }
            when 'net.authorize.payment.refund.created' {
                return handleAuthNetRefundCreated(payload);
            }
            when 'net.authorize.payment.void.created' {
                return handleAuthNetVoidCreated(payload);
            }
            when 'net.authorize.payment.fraud.held' {
                return handleAuthNetFraudHeld(payload);
            }
            when 'net.authorize.payment.fraud.declined' {
                return handleAuthNetFraudDeclined(payload);
            }
            when else {
                // Check for Silent Post (transaction response)
                if (data.containsKey('x_trans_id')) {
                    return handleAuthNetSilentPost(data);
                }
                return new WebhookResult(true, 'Event type not handled: ' + eventType);
            }
        }
    }
    
    /**
     * @description Handle Braintree webhooks
     */
    private static WebhookResult handleBraintreeWebhook(String body, Map<String, String> headers) {
        // Braintree sends bt_signature and bt_payload
        // In production, verify using Braintree SDK
        
        Map<String, Object> notification = (Map<String, Object>) JSON.deserializeUntyped(body);
        String kind = (String) notification.get('kind');
        
        switch on kind {
            when 'transaction_settled' {
                return handleBraintreeSettlement(notification, 'settled');
            }
            when 'transaction_settlement_declined' {
                return handleBraintreeSettlement(notification, 'declined');
            }
            when 'transaction_disbursed' {
                return handleBraintreeSettlement(notification, 'disbursed');
            }
            when 'dispute_opened' {
                return handleBraintreeDispute(notification, 'opened');
            }
            when 'dispute_lost' {
                return handleBraintreeDispute(notification, 'lost');
            }
            when 'dispute_won' {
                return handleBraintreeDispute(notification, 'won');
            }
            when else {
                return new WebhookResult(true, 'Event type not handled: ' + kind);
            }
        }
    }
    
    // ==================== Stripe Event Handlers ====================
    
    private static WebhookResult handleStripePaymentSuccess(Map<String, Object> paymentIntent) {
        String transactionId = (String) paymentIntent.get('id');
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found: ' + transactionId);
        }
        
        pymts__Transaction__c txn = txns[0];
        txn.pymts__Status__c = 'Approved';
        txn.pymts__Settlement_Status__c = 'Settled';
        txn.pymts__Settlement_Date__c = DateTime.now();
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        update txn;
        
        createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Payment Succeeded', 
            'Payment settled via Stripe webhook');
        
        return new WebhookResult(true, 'Payment success processed');
    }
    
    private static WebhookResult handleStripePaymentFailed(Map<String, Object> paymentIntent) {
        String transactionId = (String) paymentIntent.get('id');
        Map<String, Object> lastError = (Map<String, Object>) paymentIntent.get('last_payment_error');
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        txn.pymts__Status__c = 'Declined';
        txn.pymts__Settlement_Status__c = 'Settlement Error';
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        if (lastError != null) {
            txn.pymts__Response_Message__c = (String) lastError.get('message');
        }
        
        update txn;
        
        // Reverse invoice payment
        reverseInvoicePayment(txn.Id);
        
        createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Payment Failed', 
            'Payment failed: ' + (lastError != null ? (String) lastError.get('message') : 'Unknown error'));
        
        return new WebhookResult(true, 'Payment failure processed');
    }
    
    private static WebhookResult handleStripeChargeSucceeded(Map<String, Object> charge) {
        String chargeId = (String) charge.get('id');
        String paymentIntentId = (String) charge.get('payment_intent');
        
        // Try to find by charge ID or payment intent ID
        String searchId = paymentIntentId != null ? paymentIntentId : chargeId;
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(searchId);
        if (txns.isEmpty() && paymentIntentId != null) {
            txns = findTransactionsByGatewayId(chargeId);
        }
        
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        
        // Only update if not already settled
        if (txn.pymts__Settlement_Status__c != 'Settled') {
            txn.pymts__Settlement_Status__c = 'Settled';
            txn.pymts__Settlement_Date__c = DateTime.now();
            txn.pymts__Last_Sync_Date__c = DateTime.now();
            update txn;
            
            createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Charge Succeeded', 
                'Charge settled via webhook');
        }
        
        return new WebhookResult(true, 'Charge success processed');
    }
    
    private static WebhookResult handleStripeChargeFailed(Map<String, Object> charge) {
        String chargeId = (String) charge.get('id');
        String paymentIntentId = (String) charge.get('payment_intent');
        String failureMessage = (String) charge.get('failure_message');
        String failureCode = (String) charge.get('failure_code');
        
        String searchId = paymentIntentId != null ? paymentIntentId : chargeId;
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(searchId);
        
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        txn.pymts__Status__c = 'Declined';
        txn.pymts__Settlement_Status__c = 'Settlement Error';
        txn.pymts__Response_Message__c = failureMessage;
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        // Check if this is an ACH return
        if (failureCode != null && failureCode.startsWith('bank_account')) {
            txn.pymts__Settlement_Status__c = 'Returned';
            txn.pymts__Return_Reason_Code__c = failureCode;
        }
        
        update txn;
        
        reverseInvoicePayment(txn.Id);
        
        createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Charge Failed', 
            'Charge failed: ' + failureMessage);
        
        return new WebhookResult(true, 'Charge failure processed');
    }
    
    private static WebhookResult handleStripeChargeRefunded(Map<String, Object> charge) {
        String chargeId = (String) charge.get('id');
        Object amountRefundedObj = charge.get('amount_refunded');
        Decimal amountRefunded = amountRefundedObj != null ? 
            Decimal.valueOf(String.valueOf(amountRefundedObj)) / 100 : 0;
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(chargeId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        
        if (amountRefunded >= txn.pymts__Amount__c) {
            txn.pymts__Status__c = 'Refunded';
        } else {
            txn.pymts__Status__c = 'Partially Refunded';
        }
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        update txn;
        
        createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Charge Refunded', 
            'Refund of $' + amountRefunded);
        
        return new WebhookResult(true, 'Refund processed');
    }
    
    private static WebhookResult handleStripeDispute(Map<String, Object> dispute, String action) {
        String chargeId = (String) dispute.get('charge');
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(chargeId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        
        // Create or update dispute record
        // Note: Would need pymts__Dispute__c object fully implemented
        
        createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Dispute ' + action, 
            'Dispute ' + action + ' for charge ' + chargeId);
        
        return new WebhookResult(true, 'Dispute ' + action + ' processed');
    }
    
    private static WebhookResult handleStripeACHProcessing(Map<String, Object> paymentIntent) {
        String transactionId = (String) paymentIntent.get('id');
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        txn.pymts__Settlement_Status__c = 'Pending Settlement';
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        // Set expected settlement date (3-5 business days)
        txn.pymts__Expected_Settlement_Date__c = calculateExpectedSettlement(Date.today());
        
        update txn;
        
        return new WebhookResult(true, 'ACH processing status updated');
    }
    
    private static WebhookResult handleStripeCardExpiring(Map<String, Object> source) {
        // Notify customer about expiring card
        String customerId = (String) source.get('customer');
        String last4 = (String) source.get('last4');
        
        // Find payment methods by customer ID
        // Send notification to update card
        
        return new WebhookResult(true, 'Card expiring notification processed');
    }
    
    // ==================== Authorize.Net Event Handlers ====================
    
    private static WebhookResult handleAuthNetPaymentCreated(Map<String, Object> payload) {
        String transactionId = String.valueOf(payload.get('id'));
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        txn.pymts__Status__c = 'Approved';
        txn.pymts__Settlement_Status__c = 'Pending Settlement';
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        update txn;
        
        return new WebhookResult(true, 'Payment created processed');
    }
    
    private static WebhookResult handleAuthNetCaptureCreated(Map<String, Object> payload) {
        String transactionId = String.valueOf(payload.get('id'));
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        txn.pymts__Settlement_Status__c = 'Settled';
        txn.pymts__Settlement_Date__c = DateTime.now();
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        
        update txn;
        
        createAuditLog(txn.Id, txn.pymts__Account__c, 'Webhook: Capture Created', 
            'Transaction captured/settled');
        
        return new WebhookResult(true, 'Capture processed');
    }
    
    private static WebhookResult handleAuthNetRefundCreated(Map<String, Object> payload) {
        String transactionId = String.valueOf(payload.get('id'));
        
        createAuditLog(null, null, 'Webhook: Refund Created', 
            'Refund created for transaction ' + transactionId);
        
        return new WebhookResult(true, 'Refund notification processed');
    }
    
    private static WebhookResult handleAuthNetVoidCreated(Map<String, Object> payload) {
        String transactionId = String.valueOf(payload.get('id'));
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (!txns.isEmpty()) {
            pymts__Transaction__c txn = txns[0];
            txn.pymts__Status__c = 'Voided';
            txn.pymts__Settlement_Status__c = 'Voided';
            txn.pymts__Last_Sync_Date__c = DateTime.now();
            update txn;
            
            reverseInvoicePayment(txn.Id);
        }
        
        return new WebhookResult(true, 'Void processed');
    }
    
    private static WebhookResult handleAuthNetFraudHeld(Map<String, Object> payload) {
        String transactionId = String.valueOf(payload.get('id'));
        
        createAuditLog(null, null, 'Webhook: Fraud Held', 
            'Transaction held for fraud review: ' + transactionId);
        
        // Send alert to admins
        
        return new WebhookResult(true, 'Fraud hold notification processed');
    }
    
    private static WebhookResult handleAuthNetFraudDeclined(Map<String, Object> payload) {
        String transactionId = String.valueOf(payload.get('id'));
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (!txns.isEmpty()) {
            pymts__Transaction__c txn = txns[0];
            txn.pymts__Status__c = 'Declined';
            txn.pymts__Response_Message__c = 'Declined due to fraud detection';
            update txn;
            
            reverseInvoicePayment(txn.Id);
        }
        
        return new WebhookResult(true, 'Fraud decline processed');
    }
    
    private static WebhookResult handleAuthNetSilentPost(Map<String, Object> data) {
        // Handle Silent Post URL callback from Authorize.Net
        String transactionId = (String) data.get('x_trans_id');
        String responseCode = (String) data.get('x_response_code');
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        
        // Response codes: 1=Approved, 2=Declined, 3=Error, 4=Held for Review
        if (responseCode == '1') {
            txn.pymts__Status__c = 'Approved';
        } else if (responseCode == '2') {
            txn.pymts__Status__c = 'Declined';
            reverseInvoicePayment(txn.Id);
        } else if (responseCode == '3') {
            txn.pymts__Status__c = 'Error';
            reverseInvoicePayment(txn.Id);
        }
        
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        update txn;
        
        return new WebhookResult(true, 'Silent post processed');
    }
    
    // ==================== Braintree Event Handlers ====================
    
    private static WebhookResult handleBraintreeSettlement(Map<String, Object> notification, String status) {
        Map<String, Object> txnData = (Map<String, Object>) notification.get('transaction');
        if (txnData == null) {
            return new WebhookResult(true, 'No transaction in notification');
        }
        
        String transactionId = (String) txnData.get('id');
        
        List<pymts__Transaction__c> txns = findTransactionsByGatewayId(transactionId);
        if (txns.isEmpty()) {
            return new WebhookResult(true, 'Transaction not found');
        }
        
        pymts__Transaction__c txn = txns[0];
        
        if (status == 'settled' || status == 'disbursed') {
            txn.pymts__Settlement_Status__c = 'Settled';
            txn.pymts__Settlement_Date__c = DateTime.now();
        } else if (status == 'declined') {
            txn.pymts__Settlement_Status__c = 'Settlement Error';
            txn.pymts__Status__c = 'Declined';
            reverseInvoicePayment(txn.Id);
        }
        
        txn.pymts__Last_Sync_Date__c = DateTime.now();
        update txn;
        
        return new WebhookResult(true, 'Settlement ' + status + ' processed');
    }
    
    private static WebhookResult handleBraintreeDispute(Map<String, Object> notification, String status) {
        Map<String, Object> dispute = (Map<String, Object>) notification.get('dispute');
        if (dispute == null) {
            return new WebhookResult(true, 'No dispute in notification');
        }
        
        String transactionId = (String) dispute.get('transaction_id');
        
        createAuditLog(null, null, 'Webhook: Braintree Dispute ' + status, 
            'Dispute ' + status + ' for transaction ' + transactionId);
        
        return new WebhookResult(true, 'Dispute ' + status + ' processed');
    }
    
    // ==================== Helper Methods ====================
    
    private static Boolean verifyStripeSignature(String payload, String signature) {
        // In production, verify using Stripe webhook secret
        // For now, accept all (implement properly before going live)
        return true;
    }
    
    private static List<pymts__Transaction__c> findTransactionsByGatewayId(String gatewayTxnId) {
        return [
            SELECT Id, Name, pymts__Status__c, pymts__Settlement_Status__c, 
                   pymts__Amount__c, pymts__Account__c, pymts__Payment_Type__c
            FROM pymts__Transaction__c
            WHERE pymts__Gateway_Transaction_Id__c = :gatewayTxnId
            LIMIT 1
        ];
    }
    
    private static Map<String, Object> parseFormData(String body) {
        Map<String, Object> result = new Map<String, Object>();
        
        for (String param : body.split('&')) {
            List<String> keyValue = param.split('=');
            if (keyValue.size() == 2) {
                result.put(
                    EncodingUtil.urlDecode(keyValue[0], 'UTF-8'),
                    EncodingUtil.urlDecode(keyValue[1], 'UTF-8')
                );
            }
        }
        
        return result;
    }
    
    private static void reverseInvoicePayment(Id transactionId) {
        List<pymts__Payment_Allocation__c> allocations = [
            SELECT Id, pymts__Invoice__c, pymts__Amount__c
            FROM pymts__Payment_Allocation__c
            WHERE pymts__Transaction__c = :transactionId
        ];
        
        if (allocations.isEmpty()) return;
        
        Set<Id> invoiceIds = new Set<Id>();
        Map<Id, Decimal> reverseAmounts = new Map<Id, Decimal>();
        
        for (pymts__Payment_Allocation__c alloc : allocations) {
            invoiceIds.add(alloc.pymts__Invoice__c);
            reverseAmounts.put(alloc.pymts__Invoice__c, alloc.pymts__Amount__c);
        }
        
        List<pymts__Invoice__c> invoices = [
            SELECT Id, pymts__Amount_Paid__c, pymts__Total_Amount__c, pymts__Status__c
            FROM pymts__Invoice__c
            WHERE Id IN :invoiceIds
        ];
        
        for (pymts__Invoice__c inv : invoices) {
            Decimal reverseAmount = reverseAmounts.get(inv.Id);
            inv.pymts__Amount_Paid__c = Math.max(0, inv.pymts__Amount_Paid__c - reverseAmount);
            
            if (inv.pymts__Amount_Paid__c <= 0) {
                inv.pymts__Status__c = 'Pending';
            } else if (inv.pymts__Amount_Paid__c < inv.pymts__Total_Amount__c) {
                inv.pymts__Status__c = 'Partially Paid';
            }
        }
        
        update invoices;
    }
    
    private static void createAuditLog(Id transactionId, Id accountId, String action, String details) {
        pymts__Audit_Log__c log = new pymts__Audit_Log__c(
            pymts__Transaction__c = transactionId,
            pymts__Account__c = accountId,
            pymts__Action__c = action,
            pymts__Details__c = details,
            pymts__Timestamp__c = DateTime.now()
        );
        insert log;
    }
    
    private static void logWebhook(String gatewayType, String body, Map<String, String> headers) {
        System.debug('Webhook received from ' + gatewayType);
        System.debug('Body: ' + body.abbreviate(5000));
    }
    
    private static Date calculateExpectedSettlement(Date startDate) {
        Integer businessDays = 4;
        Date settlementDate = startDate;
        Integer daysAdded = 0;
        
        while (daysAdded < businessDays) {
            settlementDate = settlementDate.addDays(1);
            Datetime dt = DateTime.newInstance(settlementDate, Time.newInstance(0, 0, 0, 0));
            String dayOfWeek = dt.format('E');
            if (dayOfWeek != 'Sat' && dayOfWeek != 'Sun') {
                daysAdded++;
            }
        }
        
        return settlementDate;
    }
    
    // ==================== Inner Classes ====================
    
    private class WebhookResult {
        public Boolean success;
        public String message;
        
        public WebhookResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }
}
