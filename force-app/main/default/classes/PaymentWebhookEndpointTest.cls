/**
 * @description Test class for PaymentWebhookEndpoint
 */
@isTest
private class PaymentWebhookEndpointTest {
    
    @TestSetup
    static void setupTestData() {
        // Create account
        Account testAccount = new Account(Name = 'Test Company');
        insert testAccount;
        
        // Create gateway
        pymts__Payment_Gateway__c gateway = new pymts__Payment_Gateway__c(
            Name = 'Test Gateway',
            pymts__Gateway_Type__c = 'Stripe',
            pymts__Active__c = true,
            pymts__Is_Default__c = true,
            pymts__Environment__c = 'Test'
        );
        insert gateway;
        
        // Create invoice
        pymts__Invoice__c invoice = new pymts__Invoice__c(
            pymts__Account__c = testAccount.Id,
            pymts__Total_Amount__c = 100.00,
            pymts__Amount_Paid__c = 100.00,
            pymts__Status__c = 'Paid',
            pymts__Due_Date__c = Date.today()
        );
        insert invoice;
        
        // Create transaction
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 100.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved',
            pymts__Settlement_Status__c = 'Pending',
            pymts__Gateway_Transaction_Id__c = 'pi_test_webhook'
        );
        insert txn;
        
        // Create allocation
        pymts__Payment_Allocation__c alloc = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = txn.Id,
            pymts__Invoice__c = invoice.Id,
            pymts__Amount__c = 100.00
        );
        insert alloc;
    }
    
    @isTest
    static void testStripePaymentSucceeded() {
        String webhookBody = '{"type":"payment_intent.succeeded","data":{"object":{"id":"pi_test_webhook","status":"succeeded","amount":10000}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Stripe-Signature', 't=1234567890,v1=test_signature');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify transaction was updated
        pymts__Transaction__c txn = [
            SELECT pymts__Settlement_Status__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Settled', txn.pymts__Settlement_Status__c, 'Should be settled');
    }
    
    @isTest
    static void testStripePaymentFailed() {
        String webhookBody = '{"type":"payment_intent.payment_failed","data":{"object":{"id":"pi_test_webhook","status":"failed","last_payment_error":{"message":"Card declined"}}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify transaction was updated
        pymts__Transaction__c txn = [
            SELECT pymts__Status__c, pymts__Settlement_Status__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Declined', txn.pymts__Status__c, 'Should be declined');
        
        // Verify invoice was reversed
        pymts__Invoice__c invoice = [
            SELECT pymts__Amount_Paid__c, pymts__Status__c
            FROM pymts__Invoice__c LIMIT 1
        ];
        System.assertEquals(0, invoice.pymts__Amount_Paid__c, 'Payment should be reversed');
    }
    
    @isTest
    static void testStripeChargeRefunded() {
        // First set transaction as settled
        pymts__Transaction__c txn = [SELECT Id FROM pymts__Transaction__c LIMIT 1];
        txn.pymts__Settlement_Status__c = 'Settled';
        update txn;
        
        String webhookBody = '{"type":"charge.refunded","data":{"object":{"id":"pi_test_webhook","amount_refunded":10000}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify transaction status
        txn = [
            SELECT pymts__Status__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Refunded', txn.pymts__Status__c, 'Should be refunded');
    }
    
    @isTest
    static void testStripeACHProcessing() {
        String webhookBody = '{"type":"payment_intent.processing","data":{"object":{"id":"pi_test_webhook","status":"processing"}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify settlement status
        pymts__Transaction__c txn = [
            SELECT pymts__Settlement_Status__c, pymts__Expected_Settlement_Date__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Pending Settlement', txn.pymts__Settlement_Status__c, 'Should be pending settlement');
        System.assertNotEquals(null, txn.pymts__Expected_Settlement_Date__c, 'Expected date should be set');
    }
    
    @isTest
    static void testStripeDisputeCreated() {
        String webhookBody = '{"type":"charge.dispute.created","data":{"object":{"charge":"pi_test_webhook","amount":10000}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify audit log was created
        List<pymts__Audit_Log__c> logs = [
            SELECT pymts__Action__c FROM pymts__Audit_Log__c
            WHERE pymts__Action__c LIKE '%Dispute%'
        ];
        System.assert(!logs.isEmpty(), 'Dispute audit log should be created');
    }
    
    @isTest
    static void testAuthorizeNetPaymentCreated() {
        // Create AuthNet transaction
        pymts__Payment_Gateway__c authNetGateway = new pymts__Payment_Gateway__c(
            Name = 'AuthNet Test',
            pymts__Gateway_Type__c = 'Authorize.Net',
            pymts__Active__c = true,
            pymts__Environment__c = 'Test'
        );
        insert authNetGateway;
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        pymts__Transaction__c authNetTxn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = authNetGateway.Id,
            pymts__Amount__c = 150.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Pending',
            pymts__Settlement_Status__c = 'Pending',
            pymts__Gateway_Transaction_Id__c = '12345678'
        );
        insert authNetTxn;
        
        String webhookBody = '{"eventType":"net.authorize.payment.authcapture.created","payload":{"id":"12345678"}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/authorizenet';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify transaction was updated
        authNetTxn = [
            SELECT pymts__Status__c, pymts__Settlement_Status__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = '12345678'
        ];
        System.assertEquals('Approved', authNetTxn.pymts__Status__c, 'Should be approved');
    }
    
    @isTest
    static void testAuthorizeNetSilentPost() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 75.00,
            pymts__Status__c = 'Pending',
            pymts__Gateway_Transaction_Id__c = '87654321'
        );
        insert txn;
        
        String webhookBody = 'x_trans_id=87654321&x_response_code=1&x_amount=75.00';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/authorizenet';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/x-www-form-urlencoded');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify transaction was updated
        txn = [
            SELECT pymts__Status__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = '87654321'
        ];
        System.assertEquals('Approved', txn.pymts__Status__c, 'Should be approved');
    }
    
    @isTest
    static void testBraintreeSettlement() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 250.00,
            pymts__Status__c = 'Approved',
            pymts__Settlement_Status__c = 'Pending',
            pymts__Gateway_Transaction_Id__c = 'bt_txn_123'
        );
        insert txn;
        
        String webhookBody = '{"kind":"transaction_settled","transaction":{"id":"bt_txn_123"}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/braintree';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(200, res.statusCode, 'Should return 200');
        
        // Verify transaction was updated
        txn = [
            SELECT pymts__Settlement_Status__c 
            FROM pymts__Transaction__c 
            WHERE pymts__Gateway_Transaction_Id__c = 'bt_txn_123'
        ];
        System.assertEquals('Settled', txn.pymts__Settlement_Status__c, 'Should be settled');
    }
    
    @isTest
    static void testUnknownGateway() {
        String webhookBody = '{"test":"data"}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/unknown';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        System.assertEquals(400, res.statusCode, 'Should return 400 for unknown gateway');
    }
    
    @isTest
    static void testUnhandledEventType() {
        String webhookBody = '{"type":"unknown.event.type","data":{"object":{"id":"test"}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        // Should still return 200 to acknowledge receipt
        System.assertEquals(200, res.statusCode, 'Should return 200 for unhandled event');
    }
    
    @isTest
    static void testTransactionNotFound() {
        String webhookBody = '{"type":"payment_intent.succeeded","data":{"object":{"id":"pi_nonexistent"}}}';
        
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/pymt/webhook/stripe';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(webhookBody);
        req.addHeader('Content-Type', 'application/json');
        
        RestResponse res = new RestResponse();
        RestContext.request = req;
        RestContext.response = res;
        
        Test.startTest();
        PaymentWebhookEndpoint.handleWebhook();
        Test.stopTest();
        
        // Should still return 200 (transaction not found is not an error)
        System.assertEquals(200, res.statusCode, 'Should return 200');
    }
}
