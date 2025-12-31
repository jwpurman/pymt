/**
 * @description Test class for AuthorizeNetGateway
 */
@isTest
private class AuthorizeNetGatewayTest {
    
    @TestSetup
    static void setupTestData() {
        pymtTest__Payment_Gateway__c gateway = new pymtTest__Payment_Gateway__c(
            Name = 'Test Authorize.Net',
            pymtTest__Gateway_Type__c = 'Authorize.Net',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test',
            pymtTest__Public_Key__c = 'test_client_key'
        );
        insert gateway;
    }
    
    @isTest
    static void testGetGatewayType() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        Test.startTest();
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        String gatewayType = authNetGateway.getGatewayType();
        Test.stopTest();
        
        System.assertEquals('Authorize.Net', gatewayType, 'Gateway type should be Authorize.Net');
    }
    
    @isTest
    static void testGetClientLibraryUrl() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        Test.startTest();
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        String url = authNetGateway.getClientLibraryUrl();
        Test.stopTest();
        
        System.assert(url.contains('authorize.net'), 'Client library URL should be Accept.js');
    }
    
    @isTest
    static void testSaleSuccess() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 100.00;
        request.currency_x = 'USD';
        request.cardToken = 'COMMON.ACCEPT.INAPP.PAYMENT:encrypted_data_12345';
        request.description = 'Test payment';
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.sale(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Sale should be successful');
        System.assertEquals('Approved', response.status, 'Status should be Approved');
    }
    
    @isTest
    static void testSaleDeclined() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 100.00;
        request.cardToken = 'COMMON.ACCEPT.INAPP.PAYMENT:declined_12345';
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentDeclinedMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.sale(request);
        Test.stopTest();
        
        System.assertEquals(false, response.success, 'Sale should be declined');
    }
    
    @isTest
    static void testAuthorize() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        PaymentRequest request = new PaymentRequest();
        request.amount = 150.00;
        request.cardToken = 'COMMON.ACCEPT.INAPP.PAYMENT:auth_12345';
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.authorize(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Authorization should be successful');
    }
    
    @isTest
    static void testCapture() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.capture('12345678', 150.00);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Capture should be successful');
    }
    
    @isTest
    static void testRefund() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.refund('12345678', 50.00);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Refund should be successful');
    }
    
    @isTest
    static void testVoidTransaction() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.voidTransaction('12345678');
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Void should be successful');
    }
    
    @isTest
    static void testCreateCustomer() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        CustomerRequest request = new CustomerRequest();
        request.email = 'test@example.com';
        request.description = 'Test customer';
        
        Test.setMock(HttpCalloutMock.class, new AuthNetCustomerMock());
        
        Test.startTest();
        CustomerResponse response = authNetGateway.createCustomer(request);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'Customer creation should be successful');
    }
    
    @isTest
    static void testGetTransactionDetails() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetTransactionDetailsMock());
        
        Test.startTest();
        AuthorizeNetGateway.TransactionDetails details = authNetGateway.getTransactionDetails('12345678');
        Test.stopTest();
        
        System.assertEquals(true, details.success, 'Should get transaction details');
        System.assertEquals('12345678', details.transactionId, 'Transaction ID should match');
        System.assertEquals('settledSuccessfully', details.settlementState, 'Should be settled');
    }
    
    @isTest
    static void testGetTransactionDetailsWithReturn() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetTransactionReturnedMock());
        
        Test.startTest();
        AuthorizeNetGateway.TransactionDetails details = authNetGateway.getTransactionDetails('12345678');
        Test.stopTest();
        
        System.assertEquals(true, details.success, 'Should get transaction details');
        System.assertEquals(true, details.isReturned, 'Should be marked as returned');
        System.assertEquals('R01', details.returnReasonCode, 'Return code should be R01');
    }
    
    @isTest
    static void testGetUnsettledTransactions() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetUnsettledListMock());
        
        Test.startTest();
        List<AuthorizeNetGateway.TransactionDetails> transactions = authNetGateway.getUnsettledTransactions();
        Test.stopTest();
        
        System.assertEquals(2, transactions.size(), 'Should return 2 unsettled transactions');
    }
    
    @isTest
    static void testGetSettledBatches() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        Test.setMock(HttpCalloutMock.class, new AuthNetBatchListMock());
        
        Test.startTest();
        List<AuthorizeNetGateway.BatchDetails> batches = authNetGateway.getSettledBatches(
            Date.today().addDays(-7), Date.today()
        );
        Test.stopTest();
        
        System.assertEquals(1, batches.size(), 'Should return 1 batch');
    }
    
    @isTest
    static void testProcessACHPayment() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        AuthorizeNetGateway.ACHPaymentRequest achRequest = new AuthorizeNetGateway.ACHPaymentRequest();
        achRequest.amount = 500.00;
        achRequest.accountType = 'checking';
        achRequest.routingNumber = '121000248';
        achRequest.accountNumber = '12345678';
        achRequest.nameOnAccount = 'John Doe';
        achRequest.echeckType = 'WEB';
        achRequest.bankName = 'Test Bank';
        achRequest.billingName = 'John Doe';
        
        Test.setMock(HttpCalloutMock.class, new AuthNetPaymentSuccessMock());
        
        Test.startTest();
        PaymentResponse response = authNetGateway.processACHPayment(achRequest);
        Test.stopTest();
        
        System.assertEquals(true, response.success, 'ACH payment should be successful');
        System.assertEquals('ACH', response.additionalData.get('paymentType'), 'Should be marked as ACH');
    }
    
    @isTest
    static void testCreateToken() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        AuthorizeNetGateway authNetGateway = new AuthorizeNetGateway(gateway.Id);
        
        TokenRequest request = new TokenRequest();
        request.cardNumber = '4111111111111111';
        
        Test.startTest();
        TokenResponse response = authNetGateway.createToken(request);
        Test.stopTest();
        
        // Server-side tokenization not supported - use Accept.js
        System.assertEquals(false, response.success, 'Should indicate to use Accept.js');
    }
    
    // ==================== Mock Classes ====================
    
    private class AuthNetPaymentSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"transactionResponse":{"responseCode":"1","transId":"12345678","accountNumber":"XXXX4242","accountType":"Visa"},"messages":{"resultCode":"Ok","message":[{"code":"I00001","text":"Successful."}]}}');
            return res;
        }
    }
    
    private class AuthNetPaymentDeclinedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"transactionResponse":{"responseCode":"2","errors":[{"errorCode":"2","errorText":"This transaction has been declined."}]},"messages":{"resultCode":"Ok"}}');
            return res;
        }
    }
    
    private class AuthNetCustomerMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"customerProfileId":"12345","messages":{"resultCode":"Ok","message":[{"code":"I00001","text":"Successful."}]}}');
            return res;
        }
    }
    
    private class AuthNetTransactionDetailsMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"transaction":{"transId":"12345678","transactionStatus":"settledSuccessfully","settlementState":"settledSuccessfully","settleAmount":100.00,"submitTimeUTC":"2024-01-15T10:30:00Z","batch":{"batchId":"batch123","settlementTimeUTC":"2024-01-15T18:00:00Z","settlementState":"settledSuccessfully"}},"messages":{"resultCode":"Ok"}}');
            return res;
        }
    }
    
    private class AuthNetTransactionReturnedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"transaction":{"transId":"12345678","transactionStatus":"returned","returnedItems":[{"code":"R01","description":"Insufficient Funds"}]},"messages":{"resultCode":"Ok"}}');
            return res;
        }
    }
    
    private class AuthNetUnsettledListMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"transactions":[{"transId":"111","transactionStatus":"authorizedPendingCapture","settleAmount":50.00},{"transId":"222","transactionStatus":"capturedPendingSettlement","settleAmount":75.00}],"messages":{"resultCode":"Ok"}}');
            return res;
        }
    }
    
    private class AuthNetBatchListMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"batchList":[{"batchId":"batch123","settlementState":"settledSuccessfully","settlementTimeUTC":"2024-01-15T18:00:00Z"}],"messages":{"resultCode":"Ok"}}');
            return res;
        }
    }
}
