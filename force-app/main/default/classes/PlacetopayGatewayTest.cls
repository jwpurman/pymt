/**
 * @description Test class for PlacetopayGateway
 */
@isTest
private class PlacetopayGatewayTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test gateway
        pymtTest__Payment_Gateway__c gateway = new pymtTest__Payment_Gateway__c(
            Name = 'Test Placetopay Gateway',
            pymtTest__Gateway_Type__c = 'Placetopay',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test'
        );
        insert gateway;
    }
    
    @isTest
    static void testGetGatewayType() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway.Id);
        
        System.assertEquals('Placetopay', ptpGateway.getGatewayType(), 'Gateway type should be Placetopay');
    }
    
    @isTest
    static void testGetClientLibraryUrl() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway.Id);
        
        String url = ptpGateway.getClientLibraryUrl();
        System.assert(url.contains('placetopay.com'), 'Should return Placetopay JS URL');
    }
    
    @isTest
    static void testSaleSuccess() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 100.00;
        request.currency_x = 'USD';
        request.paymentMethodToken = 'tok_test_123456';
        request.idempotencyKey = 'TEST-' + String.valueOf(DateTime.now().getTime());
        request.description = 'Test payment';
        request.billingEmail = 'test@example.com';
        request.billingName = 'John Doe';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopaySuccessMock());
        PaymentResponse response = ptpGateway.sale(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Payment should succeed');
        System.assertNotEquals(null, response.transactionId, 'Transaction ID should be returned');
    }
    
    @isTest
    static void testSaleFailure() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 100.00;
        request.currency_x = 'USD';
        request.paymentMethodToken = 'tok_declined';
        request.idempotencyKey = 'TEST-FAIL-' + String.valueOf(DateTime.now().getTime());
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopayDeclineMock());
        PaymentResponse response = ptpGateway.sale(request);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Payment should fail');
        System.assert(String.isNotBlank(response.errorMessage), 'Error message should be present');
    }
    
    @isTest
    static void testAuthorize() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 250.00;
        request.currency_x = 'USD';
        request.idempotencyKey = 'AUTH-' + String.valueOf(DateTime.now().getTime());
        request.description = 'Test authorization';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopaySessionMock());
        PaymentResponse response = ptpGateway.authorize(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Session creation should succeed');
        System.assertNotEquals(null, response.additionalData.get('processUrl'), 'Redirect URL should be returned');
    }
    
    @isTest
    static void testRefund() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopayRefundMock());
        PaymentResponse response = ptpGateway.refund('12345', 50.00);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Refund should succeed');
    }
    
    @isTest
    static void testVoidTransaction() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopayRefundMock());
        PaymentResponse response = ptpGateway.voidTransaction('12345');
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Void should succeed');
    }
    
    @isTest
    static void testCreateToken() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        TokenRequest tokenRequest = new TokenRequest();
        tokenRequest.cardNumber = '4111111111111111';
        tokenRequest.expirationMonth = '12';
        tokenRequest.expirationYear = '2025';
        tokenRequest.cvv = '123';
        tokenRequest.cardholderName = 'Jane Doe';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopayTokenMock());
        TokenResponse response = ptpGateway.createToken(tokenRequest);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Token creation should succeed');
        System.assertNotEquals(null, response.token, 'Token should be returned');
    }
    
    @isTest
    static void testCapture() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        Test.startTest();
        PaymentResponse response = ptpGateway.capture('12345', 100.00);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Capture should return not supported');
    }
    
    @isTest
    static void testCreateCustomer() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        CustomerRequest customerRequest = new CustomerRequest();
        customerRequest.email = 'test@example.com';
        customerRequest.name = 'Test Customer';
        
        Test.startTest();
        CustomerResponse response = ptpGateway.createCustomer(customerRequest);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Create customer should return not supported');
    }
    
    @isTest
    static void testGetSessionStatus() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id, Name, pymtTest__Gateway_Type__c, pymtTest__Active__c, 
                                                   pymtTest__Environment__c, pymtTest__Public_Key__c, pymtTest__Is_Default__c 
                                            FROM pymtTest__Payment_Gateway__c LIMIT 1];
        PlacetopayGateway ptpGateway = new PlacetopayGateway(gateway);
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new PlacetopayStatusMock());
        Map<String, Object> status = ptpGateway.getSessionStatus('123456');
        Test.stopTest();
        
        System.assertNotEquals(null, status, 'Status should be returned');
    }
    
    @isTest
    static void testGatewayFactoryCreatesPlacetopay() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        Test.startTest();
        PaymentGateway createdGateway = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertEquals('Placetopay', createdGateway.getGatewayType(), 'Factory should create Placetopay gateway');
    }
    
    // Mock classes
    private class PlacetopaySuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":{"status":"APPROVED","reason":"00","message":"Approved"},"requestId":123456,"internalReference":"987654","authorization":"AUTH123","payment":[{"internalReference":"987654","authorization":"AUTH123","status":{"status":"APPROVED","message":"Transaction approved"}}]}');
            return res;
        }
    }
    
    private class PlacetopayDeclineMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":{"status":"REJECTED","reason":"05","message":"Transaction declined - insufficient funds"}}');
            return res;
        }
    }
    
    private class PlacetopaySessionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":{"status":"OK","reason":"PC","message":"Session created"},"requestId":123456,"processUrl":"https://checkout-test.placetopay.com/spa/session/123456/abc123"}');
            return res;
        }
    }
    
    private class PlacetopayRefundMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":{"status":"APPROVED","message":"Transaction reversed"},"internalReference":"987654"}');
            return res;
        }
    }
    
    private class PlacetopayTokenMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"status":{"status":"OK","message":"Instrument tokenized"},"instrument":{"token":{"token":"e07ca9986cf0ecac8a557fa11c07bf37ea35e9e3e3a4180c49","lastDigits":"1111","franchise":"visa","validUntil":"2025-12-31"}}}');
            return res;
        }
    }
    
    private class PlacetopayStatusMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"requestId":123456,"status":{"status":"APPROVED","message":"Session completed"},"payment":[{"status":{"status":"APPROVED"},"internalReference":"987654"}]}');
            return res;
        }
    }
}
