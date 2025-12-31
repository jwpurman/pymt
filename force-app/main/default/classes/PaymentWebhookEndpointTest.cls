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
        pymtTest__Payment_Gateway__c gateway = new pymtTest__Payment_Gateway__c(
            Name = 'Test Gateway',
            pymtTest__Gateway_Type__c = 'Stripe',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test'
        );
        insert gateway;
        
        // Create invoice
        pymtTest__Invoice__c invoice = new pymtTest__Invoice__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Total_Amount__c = 100.00,
            pymtTest__Amount_Paid__c = 100.00,
            pymtTest__Status__c = 'Paid',
            pymtTest__Due_Date__c = Date.today()
        );
        insert invoice;
        
        // Create transaction
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Type__c = 'Sale',
            pymtTest__Status__c = 'Approved',
            pymtTest__Settlement_Status__c = 'Pending',
            pymtTest__Gateway_Transaction_Id__c = 'pi_test_webhook'
        );
        insert txn;
        
        // Create allocation
        pymtTest__Payment_Allocation__c alloc = new pymtTest__Payment_Allocation__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Invoice__c = invoice.Id,
            pymtTest__Amount__c = 100.00
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
        pymtTest__Transaction__c txn = [
            SELECT pymtTest__Settlement_Status__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Settled', txn.pymtTest__Settlement_Status__c, 'Should be settled');
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
        pymtTest__Transaction__c txn = [
            SELECT pymtTest__Status__c, pymtTest__Settlement_Status__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Declined', txn.pymtTest__Status__c, 'Should be declined');
        
        // Verify invoice was reversed
        pymtTest__Invoice__c invoice = [
            SELECT pymtTest__Amount_Paid__c, pymtTest__Status__c
            FROM pymtTest__Invoice__c LIMIT 1
        ];
        System.assertEquals(0, invoice.pymtTest__Amount_Paid__c, 'Payment should be reversed');
    }
    
    @isTest
    static void testStripeChargeRefunded() {
        // First set transaction as settled
        pymtTest__Transaction__c txn = [SELECT Id FROM pymtTest__Transaction__c LIMIT 1];
        txn.pymtTest__Settlement_Status__c = 'Settled';
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
            SELECT pymtTest__Status__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Refunded', txn.pymtTest__Status__c, 'Should be refunded');
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
        pymtTest__Transaction__c txn = [
            SELECT pymtTest__Settlement_Status__c, pymtTest__Expected_Settlement_Date__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = 'pi_test_webhook'
        ];
        System.assertEquals('Pending Settlement', txn.pymtTest__Settlement_Status__c, 'Should be pending settlement');
        System.assertNotEquals(null, txn.pymtTest__Expected_Settlement_Date__c, 'Expected date should be set');
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
        List<pymtTest__Audit_Log__c> logs = [
            SELECT pymtTest__Action__c FROM pymtTest__Audit_Log__c
            WHERE pymtTest__Action__c LIKE '%Dispute%'
        ];
        System.assert(!logs.isEmpty(), 'Dispute audit log should be created');
    }
    
    @isTest
    static void testAuthorizeNetPaymentCreated() {
        // Create AuthNet transaction
        pymtTest__Payment_Gateway__c authNetGateway = new pymtTest__Payment_Gateway__c(
            Name = 'AuthNet Test',
            pymtTest__Gateway_Type__c = 'Authorize.Net',
            pymtTest__Active__c = true,
            pymtTest__Environment__c = 'Test'
        );
        insert authNetGateway;
        
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        
        pymtTest__Transaction__c authNetTxn = new pymtTest__Transaction__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = authNetGateway.Id,
            pymtTest__Amount__c = 150.00,
            pymtTest__Type__c = 'Sale',
            pymtTest__Status__c = 'Pending',
            pymtTest__Settlement_Status__c = 'Pending',
            pymtTest__Gateway_Transaction_Id__c = '12345678'
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
            SELECT pymtTest__Status__c, pymtTest__Settlement_Status__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = '12345678'
        ];
        System.assertEquals('Approved', authNetTxn.pymtTest__Status__c, 'Should be approved');
    }
    
    @isTest
    static void testAuthorizeNetSilentPost() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Amount__c = 75.00,
            pymtTest__Status__c = 'Pending',
            pymtTest__Gateway_Transaction_Id__c = '87654321'
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
            SELECT pymtTest__Status__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = '87654321'
        ];
        System.assertEquals('Approved', txn.pymtTest__Status__c, 'Should be approved');
    }
    
    @isTest
    static void testBraintreeSettlement() {
        Account testAccount = [SELECT Id FROM Account LIMIT 1];
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Amount__c = 250.00,
            pymtTest__Status__c = 'Approved',
            pymtTest__Settlement_Status__c = 'Pending',
            pymtTest__Gateway_Transaction_Id__c = 'bt_txn_123'
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
            SELECT pymtTest__Settlement_Status__c 
            FROM pymtTest__Transaction__c 
            WHERE pymtTest__Gateway_Transaction_Id__c = 'bt_txn_123'
        ];
        System.assertEquals('Settled', txn.pymtTest__Settlement_Status__c, 'Should be settled');
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
