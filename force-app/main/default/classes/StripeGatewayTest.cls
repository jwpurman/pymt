/**
 * @description Test class for StripeGateway
 */
@isTest
private class StripeGatewayTest {
    
    @TestSetup
    static void setupTestData() {
        pymtTest__Payment_Gateway__c gateway = new pymtTest__Payment_Gateway__c(
            Name = 'Test Stripe',
            pymtTest__Gateway_Type__c = 'Stripe',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test',
            pymtTest__Public_Key__c = 'pk_test_12345'
        );
        insert gateway;
    }
    
    @isTest
    static void testGetGatewayType() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        Test.startTest();
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        String gatewayType = stripeGateway.getGatewayType();
        Test.stopTest();
        
        System.assertEquals('Stripe', gatewayType, 'Gateway type should be Stripe');
    }
    
    @isTest
    static void testGetClientLibraryUrl() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        Test.startTest();
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        String url = stripeGateway.getClientLibraryUrl();
        Test.stopTest();
        
        System.assertEquals('https://js.stripe.com/v3/', url, 'Client library URL should match');
    }
    
    @isTest
    static void testSaleSuccess() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 100.00;
        request.currency_x = 'USD';
        request.paymentMethodToken = 'pm_test_12345';
        request.description = 'Test payment';
        
        Test.setMock(HttpCalloutMock.class, new StripePaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.sale(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Sale should be successful');
        System.assertEquals('Approved', response.status, 'Status should be Approved');
        System.assertNotEquals(null, response.transactionId, 'Transaction ID should be set');
    }
    
    @isTest
    static void testSaleDeclined() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 100.00;
        request.currency_x = 'USD';
        request.paymentMethodToken = 'pm_test_declined';
        
        Test.setMock(HttpCalloutMock.class, new StripePaymentDeclinedMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.sale(request);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Sale should be declined');
        System.assertNotEquals(null, response.errorMessage, 'Error message should be set');
    }
    
    @isTest
    static void testAuthorize() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 150.00;
        request.currency_x = 'USD';
        request.paymentMethodToken = 'pm_test_12345';
        
        Test.setMock(HttpCalloutMock.class, new StripeAuthorizeMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.authorize(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Authorization should be successful');
        System.assertEquals('Approved', response.status, 'Status should be Approved');
    }
    
    @isTest
    static void testCapture() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new StripeCaptureMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.capture('pi_test_authorized', 150.00);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Capture should be successful');
    }
    
    @isTest
    static void testRefundFull() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new StripeRefundMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.refund('pi_test_captured', null);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Full refund should be successful');
    }
    
    @isTest
    static void testRefundPartial() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new StripeRefundMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.refund('pi_test_captured', 50.00);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Partial refund should be successful');
    }
    
    @isTest
    static void testVoidTransaction() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new StripeVoidMock());
        
        Test.startTest();
        PaymentResponse response = stripeGateway.voidTransaction('pi_test_authorized');
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Void should be successful');
    }
    
    @isTest
    static void testCreateCustomer() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        CustomerRequest request = new CustomerRequest();
        request.email = 'test@example.com';
        request.name = 'Test Customer';
        request.description = 'Test customer description';
        
        Test.setMock(HttpCalloutMock.class, new StripeCustomerMock());
        
        Test.startTest();
        CustomerResponse response = stripeGateway.createCustomer(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Customer creation should be successful');
        System.assertNotEquals(null, response.customerId, 'Customer ID should be set');
    }
    
    @isTest
    static void testAttachPaymentMethod() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new StripeAttachPaymentMethodMock());
        
        Test.startTest();
        PaymentMethodResponse response = stripeGateway.attachPaymentMethod('cus_test_12345', 'pm_test_12345');
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Attach payment method should be successful');
    }
    
    @isTest
    static void testGetChargeDetails() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new StripeChargeDetailsMock());
        
        Test.startTest();
        Map<String, Object> details = stripeGateway.getChargeDetails('pi_test_12345');
        Test.stopTest();
        
        System.assertNotEquals(null, details, 'Details should not be null');
        System.assertEquals('succeeded', details.get('status'), 'Status should be succeeded');
    }
    
    @isTest
    static void testCreateToken() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        StripeGateway stripeGateway = new StripeGateway(gateway.Id);
        
        TokenRequest request = new TokenRequest();
        request.cardNumber = '4242424242424242';
        request.expirationMonth = '12';
        request.expirationYear = String.valueOf(Date.today().year() + 2);
        request.cvv = '123';
        
        Test.startTest();
        TokenResponse response = stripeGateway.createToken(request);
        Test.stopTest();
        
        // Server-side tokenization is not supported for PCI compliance
        System.assertEquals(false, response.success, 'Token creation should fail (use Stripe.js)');
    }
    
    // ==================== Mock Classes ====================
    
    private class StripePaymentSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pi_test_12345","object":"payment_intent","status":"succeeded","amount":10000,"currency":"usd"}');
            return res;
        }
    }
    
    private class StripePaymentDeclinedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(402);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"code":"card_declined","message":"Your card was declined.","type":"card_error"}}');
            return res;
        }
    }
    
    private class StripeAuthorizeMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pi_test_auth_12345","object":"payment_intent","status":"requires_capture","amount":15000,"currency":"usd"}');
            return res;
        }
    }
    
    private class StripeCaptureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pi_test_authorized","object":"payment_intent","status":"succeeded","amount":15000}');
            return res;
        }
    }
    
    private class StripeRefundMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"re_test_12345","object":"refund","status":"succeeded","amount":5000}');
            return res;
        }
    }
    
    private class StripeVoidMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pi_test_authorized","object":"payment_intent","status":"canceled"}');
            return res;
        }
    }
    
    private class StripeCustomerMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"cus_test_12345","object":"customer","email":"test@example.com"}');
            return res;
        }
    }
    
    private class StripeAttachPaymentMethodMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pm_test_12345","object":"payment_method","customer":"cus_test_12345","card":{"brand":"visa","last4":"4242","exp_month":12,"exp_year":2025}}');
            return res;
        }
    }
    
    private class StripeChargeDetailsMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pi_test_12345","object":"payment_intent","status":"succeeded","captured":true,"amount":10000}');
            return res;
        }
    }
}
