/**
 * @description Test class for CallCenterService
 */
@isTest
private class CallCenterServiceTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        accounts.add(new Account(Name = 'Test Customer One', Phone = '555-1234'));
        accounts.add(new Account(Name = 'Test Customer Two', Phone = '555-5678'));
        accounts.add(new Account(Name = 'Acme Corporation', Phone = '555-9999'));
        insert accounts;
        
        // Create test products
        List<Product2> products = new List<Product2>();
        products.add(new Product2(Name = 'Widget Pro', ProductCode = 'WGT-PRO', IsActive = true));
        products.add(new Product2(Name = 'Widget Basic', ProductCode = 'WGT-BAS', IsActive = true));
        products.add(new Product2(Name = 'Premium Service', ProductCode = 'SVC-PRM', IsActive = true));
        insert products;
        
        // Create pricebook entries
        Id standardPbId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        pbes.add(new PricebookEntry(Pricebook2Id = standardPbId, Product2Id = products[0].Id, UnitPrice = 99.99, IsActive = true));
        pbes.add(new PricebookEntry(Pricebook2Id = standardPbId, Product2Id = products[1].Id, UnitPrice = 49.99, IsActive = true));
        pbes.add(new PricebookEntry(Pricebook2Id = standardPbId, Product2Id = products[2].Id, UnitPrice = 199.99, IsActive = true));
        insert pbes;
        
        // Create payment gateway
        pymts__Payment_Gateway__c gateway = new pymts__Payment_Gateway__c(
            Name = 'Test Stripe Gateway',
            pymts__Gateway_Type__c = 'Stripe',
            pymts__Active__c = true,
            pymts__Is_Default__c = true,
            pymts__Environment__c = 'Test'
        );
        insert gateway;
        
        // Create payment method for one account
        pymts__Payment_Method__c pm = new pymts__Payment_Method__c(
            pymts__Account__c = accounts[0].Id,
            pymts__Type__c = 'Credit Card',
            pymts__Card_Brand__c = 'Visa',
            pymts__Last_Four__c = '4242',
            pymts__Expiration_Month__c = 12,
            pymts__Expiration_Year__c = Date.today().addYears(2).year(),
            pymts__Gateway_Token__c = 'tok_test_12345',
            pymts__Active__c = true,
            pymts__Is_Primary__c = true,
            pymts__Payment_Gateway__c = gateway.Id
        );
        insert pm;
    }
    
    @isTest
    static void testSearchAccounts_ByName() {
        List<Account> results = CallCenterService.searchAccounts('Test Customer');
        System.assertEquals(2, results.size(), 'Should find two test customers');
    }
    
    @isTest
    static void testSearchAccounts_ByPhone() {
        List<Account> results = CallCenterService.searchAccounts('555-1234');
        System.assertEquals(1, results.size(), 'Should find one customer by phone');
        System.assertEquals('Test Customer One', results[0].Name);
    }
    
    @isTest
    static void testSearchAccounts_TooShort() {
        List<Account> results = CallCenterService.searchAccounts('Te');
        System.assertEquals(0, results.size(), 'Should return empty for search term < 3 chars');
    }
    
    @isTest
    static void testSearchAccounts_NoResults() {
        List<Account> results = CallCenterService.searchAccounts('ZZZZZ');
        System.assertEquals(0, results.size(), 'Should return empty for no matches');
    }
    
    @isTest
    static void testSearchAccounts_IncludesPaymentMethods() {
        List<Account> results = CallCenterService.searchAccounts('Test Customer One');
        System.assertEquals(1, results.size());
        System.assertEquals(1, results[0].pymts__Payment_Methods__r.size(), 'Should include payment methods');
    }
    
    @isTest
    static void testCreateQuickAccount_Success() {
        Test.startTest();
        Account newAccount = CallCenterService.createQuickAccount('New Customer', '555-0000', 'new@test.com');
        Test.stopTest();
        
        System.assertNotEquals(null, newAccount.Id, 'Account should be created');
        System.assertEquals('New Customer', newAccount.Name);
        System.assertEquals('555-0000', newAccount.Phone);
    }
    
    @isTest
    static void testCreateQuickAccount_MissingName() {
        try {
            CallCenterService.createQuickAccount('', '555-0000', 'new@test.com');
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account name is required'));
        }
    }
    
    @isTest
    static void testSearchProducts() {
        List<Map<String, Object>> results = CallCenterService.searchProducts('Widget');
        System.assertEquals(2, results.size(), 'Should find two widget products');
    }
    
    @isTest
    static void testSearchProducts_ByCode() {
        List<Map<String, Object>> results = CallCenterService.searchProducts('WGT-PRO');
        System.assertEquals(1, results.size(), 'Should find one product by code');
        System.assertEquals('Widget Pro', results[0].get('name'));
    }
    
    @isTest
    static void testSearchProducts_TooShort() {
        List<Map<String, Object>> results = CallCenterService.searchProducts('W');
        System.assertEquals(0, results.size(), 'Should return empty for search term < 2 chars');
    }
    
    @isTest
    static void testGetPaymentMethods() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Customer One'];
        List<pymts__Payment_Method__c> methods = CallCenterService.getPaymentMethods(acc.Id);
        System.assertEquals(1, methods.size(), 'Should find one payment method');
        System.assertEquals('4242', methods[0].pymts__Last_Four__c);
    }
    
    @isTest
    static void testGetPaymentMethods_NoMethods() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Customer Two'];
        List<pymts__Payment_Method__c> methods = CallCenterService.getPaymentMethods(acc.Id);
        System.assertEquals(0, methods.size(), 'Should return empty for account without methods');
    }
    
    @isTest
    static void testProcessCallCenterPayment_WithSavedMethod() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Customer One'];
        pymts__Payment_Method__c pm = [SELECT Id FROM pymts__Payment_Method__c WHERE pymts__Account__c = :acc.Id];
        Product2 product = [SELECT Id FROM Product2 WHERE ProductCode = 'WGT-PRO'];
        
        CallCenterService.CartItem item = new CallCenterService.CartItem();
        item.productId = product.Id;
        item.productName = 'Widget Pro';
        item.quantity = 2;
        item.unitPrice = 99.99;
        item.totalPrice = 199.98;
        
        CallCenterService.CallCenterPaymentRequest request = new CallCenterService.CallCenterPaymentRequest();
        request.accountId = acc.Id;
        request.cartItems = new List<CallCenterService.CartItem>{ item };
        request.paymentMethodId = pm.Id;
        request.paymentType = 'Card';
        request.sourceDescription = 'Test call center payment';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new StripeGatewayMock());
        CallCenterService.CallCenterPaymentResult result = CallCenterService.processCallCenterPayment(request);
        Test.stopTest();
        
        System.assertEquals(true, result.success, 'Payment should succeed');
        System.assertNotEquals(null, result.transactionId, 'Transaction ID should be returned');
        System.assertEquals(199.98, result.amount, 'Amount should match cart total');
        
        // Verify transaction was created
        pymts__Transaction__c txn = [SELECT pymts__Sales_Channel__c, pymts__Fulfillment_Status__c 
                                    FROM pymts__Transaction__c WHERE Id = :result.transactionId];
        System.assertEquals('Phone', txn.pymts__Sales_Channel__c, 'Sales channel should be Phone');
        System.assertEquals('Pending', txn.pymts__Fulfillment_Status__c, 'Fulfillment should be Pending');
        
        // Verify line items were created
        List<pymts__Transaction_Line_Item__c> lineItems = [
            SELECT pymts__Product__c, pymts__Quantity__c, pymts__Unit_Price__c
            FROM pymts__Transaction_Line_Item__c
            WHERE pymts__Transaction__c = :result.transactionId
        ];
        System.assertEquals(1, lineItems.size(), 'Should have one line item');
        System.assertEquals(2, lineItems[0].pymts__Quantity__c, 'Quantity should be 2');
    }
    
    @isTest
    static void testProcessCallCenterPayment_MultipleItems() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Customer One'];
        pymts__Payment_Method__c pm = [SELECT Id FROM pymts__Payment_Method__c WHERE pymts__Account__c = :acc.Id];
        List<Product2> products = [SELECT Id, Name FROM Product2 ORDER BY Name];
        
        List<CallCenterService.CartItem> items = new List<CallCenterService.CartItem>();
        
        CallCenterService.CartItem item1 = new CallCenterService.CartItem();
        item1.productId = products[0].Id;
        item1.quantity = 1;
        item1.unitPrice = 199.99;
        items.add(item1);
        
        CallCenterService.CartItem item2 = new CallCenterService.CartItem();
        item2.productId = products[1].Id;
        item2.quantity = 3;
        item2.unitPrice = 49.99;
        items.add(item2);
        
        CallCenterService.CallCenterPaymentRequest request = new CallCenterService.CallCenterPaymentRequest();
        request.accountId = acc.Id;
        request.cartItems = items;
        request.paymentMethodId = pm.Id;
        request.paymentType = 'Card';
        
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new StripeGatewayMock());
        CallCenterService.CallCenterPaymentResult result = CallCenterService.processCallCenterPayment(request);
        Test.stopTest();
        
        System.assertEquals(true, result.success);
        // 199.99 + (3 * 49.99) = 349.96
        System.assertEquals(349.96, result.amount);
        
        // Verify multiple line items
        Integer lineItemCount = [SELECT COUNT() FROM pymts__Transaction_Line_Item__c WHERE pymts__Transaction__c = :result.transactionId];
        System.assertEquals(2, lineItemCount, 'Should have two line items');
    }
    
    @isTest
    static void testProcessCallCenterPayment_ValidationErrors() {
        // Missing account
        CallCenterService.CallCenterPaymentRequest request1 = new CallCenterService.CallCenterPaymentRequest();
        request1.cartItems = new List<CallCenterService.CartItem>();
        
        CallCenterService.CallCenterPaymentResult result1 = CallCenterService.processCallCenterPayment(request1);
        System.assertEquals(false, result1.success);
        System.assert(result1.errorMessage.contains('Account is required'));
        
        // Empty cart
        Account acc = [SELECT Id FROM Account LIMIT 1];
        CallCenterService.CallCenterPaymentRequest request2 = new CallCenterService.CallCenterPaymentRequest();
        request2.accountId = acc.Id;
        request2.cartItems = new List<CallCenterService.CartItem>();
        
        CallCenterService.CallCenterPaymentResult result2 = CallCenterService.processCallCenterPayment(request2);
        System.assertEquals(false, result2.success);
        System.assert(result2.errorMessage.contains('Cart cannot be empty'));
    }
    
    // Mock class for Stripe API calls
    private class StripeGatewayMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id": "ch_test_123", "status": "succeeded", "amount": 19998}');
            return res;
        }
    }
}
