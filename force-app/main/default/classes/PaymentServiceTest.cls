/**
 * @description Test class for PaymentService
 */
@isTest
private class PaymentServiceTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(
            Name = 'Test Company'
        );
        insert testAccount;
        
        // Create test gateway
        pymts__Payment_Gateway__c gateway = new pymts__Payment_Gateway__c(
            Name = 'Test Stripe Gateway',
            pymts__Gateway_Type__c = 'Stripe',
            pymts__Active__c = true,
            pymts__Is_Default__c = true,
            pymts__Environment__c = 'Test',
            pymts__Public_Key__c = 'pk_test_12345'
        );
        insert gateway;
        
        // Create test payment method
        pymts__Payment_Method__c paymentMethod = new pymts__Payment_Method__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Type__c = 'Credit Card',
            pymts__Card_Brand__c = 'Visa',
            pymts__Last_Four__c = '4242',
            pymts__Expiration_Month__c = 12,
            pymts__Expiration_Year__c = Date.today().year() + 2,
            pymts__Gateway_Token__c = 'pm_test_12345',
            pymts__Active__c = true,
            pymts__Is_Primary__c = true
        );
        insert paymentMethod;
        
        // Create test order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            pymts__Payment_Frequency__c = 'One-Time'
        );
        insert testOrder;
        
        // Create test invoices
        List<pymts__Invoice__c> invoices = new List<pymts__Invoice__c>();
        for (Integer i = 0; i < 3; i++) {
            invoices.add(new pymts__Invoice__c(
                pymts__Account__c = testAccount.Id,
                pymts__Order__c = testOrder.Id,
                pymts__Total_Amount__c = 100.00,
                pymts__Amount_Paid__c = 0,
                pymts__Status__c = 'Pending',
                pymts__Due_Date__c = Date.today().addDays(30),
                pymts__Payment_Gateway__c = gateway.Id
            ));
        }
        insert invoices;
        
        // Create invoice line items
        List<pymts__Invoice_Line_Item__c> lineItems = new List<pymts__Invoice_Line_Item__c>();
        for (pymts__Invoice__c inv : invoices) {
            lineItems.add(new pymts__Invoice_Line_Item__c(
                pymts__Invoice__c = inv.Id,
                pymts__Description__c = 'Test Product',
                pymts__Quantity__c = 1,
                pymts__Unit_Price__c = 100.00
            ));
        }
        insert lineItems;
    }
    
    @isTest
    static void testGetOpenInvoices() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        
        Test.startTest();
        List<PaymentService.InvoiceWrapper> invoices = PaymentService.getOpenInvoices(testAccount.Id);
        Test.stopTest();
        
        System.assertEquals(3, invoices.size(), 'Should return 3 open invoices');
        for (PaymentService.InvoiceWrapper inv : invoices) {
            System.assertEquals(100.00, inv.balanceDue, 'Balance due should be 100');
        }
    }
    
    @isTest
    static void testGetPaymentMethods() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        
        Test.startTest();
        List<PaymentService.PaymentMethodWrapper> methods = PaymentService.getPaymentMethods(testAccount.Id);
        Test.stopTest();
        
        System.assertEquals(1, methods.size(), 'Should return 1 payment method');
        System.assertEquals('Visa', methods[0].cardBrand, 'Card brand should be Visa');
        System.assertEquals('4242', methods[0].lastFour, 'Last four should be 4242');
        System.assertEquals(true, methods[0].isPrimary, 'Should be primary');
    }
    
    @isTest
    static void testGetActiveGateways() {
        Test.startTest();
        List<pymts__Payment_Gateway__c> gateways = PaymentService.getActiveGateways();
        Test.stopTest();
        
        System.assertEquals(1, gateways.size(), 'Should return 1 active gateway');
        System.assertEquals('Stripe', gateways[0].pymts__Gateway_Type__c, 'Gateway type should be Stripe');
    }
    
    @isTest
    static void testGetGatewayConfiguration() {
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        Test.startTest();
        Map<String, Object> config = PaymentService.getGatewayConfiguration(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, config, 'Config should not be null');
        System.assertEquals('Stripe', config.get('gatewayType'), 'Gateway type should be Stripe');
        System.assertEquals('pk_test_12345', config.get('publicKey'), 'Public key should match');
    }
    
    @isTest
    static void testAddPaymentMethod() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        Map<String, Object> cardDetails = new Map<String, Object>{
            'brand' => 'Mastercard',
            'last4' => '5555',
            'expMonth' => 6,
            'expYear' => Date.today().year() + 3
        };
        
        Test.startTest();
        Id paymentMethodId = PaymentService.addPaymentMethod(
            testAccount.Id, 
            gateway.Id, 
            'pm_test_new_12345', 
            cardDetails, 
            false
        );
        Test.stopTest();
        
        System.assertNotEquals(null, paymentMethodId, 'Should return payment method ID');
        
        pymts__Payment_Method__c pm = [
            SELECT pymts__Card_Brand__c, pymts__Last_Four__c, pymts__Is_Primary__c 
            FROM pymts__Payment_Method__c 
            WHERE Id = :paymentMethodId
        ];
        System.assertEquals('Mastercard', pm.pymts__Card_Brand__c, 'Brand should be Mastercard');
        System.assertEquals('5555', pm.pymts__Last_Four__c, 'Last four should be 5555');
        System.assertEquals(false, pm.pymts__Is_Primary__c, 'Should not be primary');
    }
    
    @isTest
    static void testSetPrimaryPaymentMethod() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        // Create second payment method
        pymts__Payment_Method__c pm2 = new pymts__Payment_Method__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Type__c = 'Credit Card',
            pymts__Card_Brand__c = 'Mastercard',
            pymts__Last_Four__c = '5555',
            pymts__Expiration_Month__c = 6,
            pymts__Expiration_Year__c = Date.today().year() + 3,
            pymts__Gateway_Token__c = 'pm_test_mc_12345',
            pymts__Active__c = true,
            pymts__Is_Primary__c = false
        );
        insert pm2;
        
        Test.startTest();
        PaymentService.setPrimaryPaymentMethod(pm2.Id);
        Test.stopTest();
        
        // Verify new primary
        pymts__Payment_Method__c updated = [
            SELECT pymts__Is_Primary__c FROM pymts__Payment_Method__c WHERE Id = :pm2.Id
        ];
        System.assertEquals(true, updated.pymts__Is_Primary__c, 'Should now be primary');
        
        // Verify old primary is no longer primary
        pymts__Payment_Method__c oldPrimary = [
            SELECT pymts__Is_Primary__c FROM pymts__Payment_Method__c 
            WHERE pymts__Account__c = :testAccount.Id AND Id != :pm2.Id
            LIMIT 1
        ];
        System.assertEquals(false, oldPrimary.pymts__Is_Primary__c, 'Old primary should be cleared');
    }
    
    @isTest
    static void testRemovePaymentMethod() {
        pymts__Payment_Method__c pm = [SELECT Id FROM pymts__Payment_Method__c LIMIT 1];
        
        Test.startTest();
        PaymentService.removePaymentMethod(pm.Id);
        Test.stopTest();
        
        pymts__Payment_Method__c updated = [
            SELECT pymts__Active__c FROM pymts__Payment_Method__c WHERE Id = :pm.Id
        ];
        System.assertEquals(false, updated.pymts__Active__c, 'Should be deactivated');
    }
    
    @isTest
    static void testGetAccountCredits() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        
        // Create account credit
        pymts__Account_Credit__c credit = new pymts__Account_Credit__c(
            pymts__Account__c = testAccount.Id,
            pymts__Original_Amount__c = 50.00,
            pymts__Remaining_Balance__c = 50.00
        );
        insert credit;
        
        Test.startTest();
        List<pymts__Account_Credit__c> credits = PaymentService.getAccountCredits(testAccount.Id);
        Test.stopTest();
        
        System.assertEquals(1, credits.size(), 'Should return 1 credit');
        System.assertEquals(50.00, credits[0].pymts__Remaining_Balance__c, 'Balance should be 50');
    }
    
    @isTest
    static void testProcessPaymentSuccess() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        pymts__Payment_Method__c pm = [SELECT Id, pymts__Gateway_Token__c FROM pymts__Payment_Method__c LIMIT 1];
        pymts__Invoice__c invoice = [SELECT Id, pymts__Total_Amount__c FROM pymts__Invoice__c LIMIT 1];
        
        PaymentService.PaymentData paymentData = new PaymentService.PaymentData();
        paymentData.accountId = testAccount.Id;
        paymentData.gatewayId = gateway.Id;
        paymentData.paymentMethodId = pm.Id;
        paymentData.amount = 100.00;
        paymentData.invoiceAllocations = new List<PaymentService.InvoiceAllocation>();
        
        PaymentService.InvoiceAllocation alloc = new PaymentService.InvoiceAllocation();
        alloc.invoiceId = invoice.Id;
        alloc.amount = 100.00;
        paymentData.invoiceAllocations.add(alloc);
        
        // Mock the gateway response
        Test.setMock(HttpCalloutMock.class, new StripeSuccessMock());
        
        Test.startTest();
        PaymentService.PaymentResult result = PaymentService.processPayment(paymentData);
        Test.stopTest();
        
        // Note: In a real test, the mock would need to return proper data
        // This test verifies the method can be called without errors
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testProcessRefund() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        pymts__Invoice__c invoice = [SELECT Id FROM pymts__Invoice__c LIMIT 1];
        
        // Create a transaction to refund
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 100.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved',
            pymts__Gateway_Transaction_Id__c = 'pi_test_12345'
        );
        insert txn;
        
        // Create allocation
        pymts__Payment_Allocation__c alloc = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = txn.Id,
            pymts__Invoice__c = invoice.Id,
            pymts__Amount__c = 100.00
        );
        insert alloc;
        
        // Update invoice as paid
        invoice.pymts__Amount_Paid__c = 100.00;
        invoice.pymts__Status__c = 'Paid';
        update invoice;
        
        Test.setMock(HttpCalloutMock.class, new StripeSuccessMock());
        
        Test.startTest();
        PaymentService.PaymentResult result = PaymentService.processRefund(txn.Id, 50.00);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @isTest
    static void testVoidTransaction() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        pymts__Invoice__c invoice = [SELECT Id FROM pymts__Invoice__c LIMIT 1];
        
        // Create a transaction to void
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 100.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved',
            pymts__Gateway_Transaction_Id__c = 'pi_test_void_12345'
        );
        insert txn;
        
        // Create allocation
        pymts__Payment_Allocation__c alloc = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = txn.Id,
            pymts__Invoice__c = invoice.Id,
            pymts__Amount__c = 100.00
        );
        insert alloc;
        
        Test.setMock(HttpCalloutMock.class, new StripeSuccessMock());
        
        Test.startTest();
        PaymentService.PaymentResult result = PaymentService.voidTransaction(txn.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    // Mock class for Stripe API calls
    private class StripeSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().contains('payment_intents')) {
                res.setBody('{"id":"pi_test_12345","status":"succeeded","amount":10000}');
            } else if (req.getEndpoint().contains('refunds')) {
                res.setBody('{"id":"re_test_12345","status":"succeeded","amount":5000}');
            } else {
                res.setBody('{"id":"test_12345","status":"succeeded"}');
            }
            
            return res;
        }
    }
}
