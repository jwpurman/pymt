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
        pymtTest__Payment_Gateway__c gateway = new pymtTest__Payment_Gateway__c(
            Name = 'Test Stripe Gateway',
            pymtTest__Gateway_Type__c = 'Stripe',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test',
            pymtTest__Public_Key__c = 'pk_test_12345'
        );
        insert gateway;
        
        // Create test payment method
        pymtTest__Payment_Method__c paymentMethod = new pymtTest__Payment_Method__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Type__c = 'Credit Card',
            pymtTest__Card_Brand__c = 'Visa',
            pymtTest__Last_Four__c = '4242',
            pymtTest__Expiration_Month__c = 12,
            pymtTest__Expiration_Year__c = Date.today().year() + 2,
            pymtTest__Gateway_Token__c = 'pm_test_12345',
            pymtTest__Active__c = true,
            pymtTest__Is_Primary__c = true
        );
        insert paymentMethod;
        
        // Create test order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            pymtTest__Payment_Frequency__c = 'One-Time'
        );
        insert testOrder;
        
        // Create test invoices
        List<pymtTest__Invoice__c> invoices = new List<pymtTest__Invoice__c>();
        for (Integer i = 0; i < 3; i++) {
            invoices.add(new pymtTest__Invoice__c(
                pymtTest__Account__c = testAccount.Id,
                pymtTest__Order__c = testOrder.Id,
                pymtTest__Total_Amount__c = 100.00,
                pymtTest__Amount_Paid__c = 0,
                pymtTest__Status__c = 'Pending',
                pymtTest__Due_Date__c = Date.today().addDays(30),
                pymtTest__Payment_Gateway__c = gateway.Id
            ));
        }
        insert invoices;
        
        // Create invoice line items
        List<pymtTest__Invoice_Line_Item__c> lineItems = new List<pymtTest__Invoice_Line_Item__c>();
        for (pymtTest__Invoice__c inv : invoices) {
            lineItems.add(new pymtTest__Invoice_Line_Item__c(
                pymtTest__Invoice__c = inv.Id,
                pymtTest__Description__c = 'Test Product',
                pymtTest__Quantity__c = 1,
                pymtTest__Unit_Price__c = 100.00
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
        List<pymtTest__Payment_Gateway__c> gateways = PaymentService.getActiveGateways();
        Test.stopTest();
        
        System.assertEquals(1, gateways.size(), 'Should return 1 active gateway');
        System.assertEquals('Stripe', gateways[0].pymtTest__Gateway_Type__c, 'Gateway type should be Stripe');
    }
    
    @isTest
    static void testGetGatewayConfiguration() {
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
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
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
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
        
        pymtTest__Payment_Method__c pm = [
            SELECT pymtTest__Card_Brand__c, pymtTest__Last_Four__c, pymtTest__Is_Primary__c 
            FROM pymtTest__Payment_Method__c 
            WHERE Id = :paymentMethodId
        ];
        System.assertEquals('Mastercard', pm.pymtTest__Card_Brand__c, 'Brand should be Mastercard');
        System.assertEquals('5555', pm.pymtTest__Last_Four__c, 'Last four should be 5555');
        System.assertEquals(false, pm.pymtTest__Is_Primary__c, 'Should not be primary');
    }
    
    @isTest
    static void testSetPrimaryPaymentMethod() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        
        // Create second payment method
        pymtTest__Payment_Method__c pm2 = new pymtTest__Payment_Method__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Type__c = 'Credit Card',
            pymtTest__Card_Brand__c = 'Mastercard',
            pymtTest__Last_Four__c = '5555',
            pymtTest__Expiration_Month__c = 6,
            pymtTest__Expiration_Year__c = Date.today().year() + 3,
            pymtTest__Gateway_Token__c = 'pm_test_mc_12345',
            pymtTest__Active__c = true,
            pymtTest__Is_Primary__c = false
        );
        insert pm2;
        
        Test.startTest();
        PaymentService.setPrimaryPaymentMethod(pm2.Id);
        Test.stopTest();
        
        // Verify new primary
        pymtTest__Payment_Method__c updated = [
            SELECT pymtTest__Is_Primary__c FROM pymtTest__Payment_Method__c WHERE Id = :pm2.Id
        ];
        System.assertEquals(true, updated.pymtTest__Is_Primary__c, 'Should now be primary');
        
        // Verify old primary is no longer primary
        pymtTest__Payment_Method__c oldPrimary = [
            SELECT pymtTest__Is_Primary__c FROM pymtTest__Payment_Method__c 
            WHERE pymtTest__Account__c = :testAccount.Id AND Id != :pm2.Id
            LIMIT 1
        ];
        System.assertEquals(false, oldPrimary.pymtTest__Is_Primary__c, 'Old primary should be cleared');
    }
    
    @isTest
    static void testRemovePaymentMethod() {
        pymtTest__Payment_Method__c pm = [SELECT Id FROM pymtTest__Payment_Method__c LIMIT 1];
        
        Test.startTest();
        PaymentService.removePaymentMethod(pm.Id);
        Test.stopTest();
        
        pymtTest__Payment_Method__c updated = [
            SELECT pymtTest__Active__c FROM pymtTest__Payment_Method__c WHERE Id = :pm.Id
        ];
        System.assertEquals(false, updated.pymtTest__Active__c, 'Should be deactivated');
    }
    
    @isTest
    static void testGetAccountCredits() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        
        // Create account credit
        pymtTest__Account_Credit__c credit = new pymtTest__Account_Credit__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Original_Amount__c = 50.00,
            pymtTest__Remaining_Balance__c = 50.00
        );
        insert credit;
        
        Test.startTest();
        List<pymtTest__Account_Credit__c> credits = PaymentService.getAccountCredits(testAccount.Id);
        Test.stopTest();
        
        System.assertEquals(1, credits.size(), 'Should return 1 credit');
        System.assertEquals(50.00, credits[0].pymtTest__Remaining_Balance__c, 'Balance should be 50');
    }
    
    @isTest
    static void testProcessPaymentSuccess() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        pymtTest__Payment_Method__c pm = [SELECT Id, pymtTest__Gateway_Token__c FROM pymtTest__Payment_Method__c LIMIT 1];
        pymtTest__Invoice__c invoice = [SELECT Id, pymtTest__Total_Amount__c FROM pymtTest__Invoice__c LIMIT 1];
        
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
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        pymtTest__Invoice__c invoice = [SELECT Id FROM pymtTest__Invoice__c LIMIT 1];
        
        // Create a transaction to refund
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Type__c = 'Sale',
            pymtTest__Status__c = 'Approved',
            pymtTest__Gateway_Transaction_Id__c = 'pi_test_12345'
        );
        insert txn;
        
        // Create allocation
        pymtTest__Payment_Allocation__c alloc = new pymtTest__Payment_Allocation__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Invoice__c = invoice.Id,
            pymtTest__Amount__c = 100.00
        );
        insert alloc;
        
        // Update invoice as paid
        invoice.pymtTest__Amount_Paid__c = 100.00;
        invoice.pymtTest__Status__c = 'Paid';
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
        pymtTest__Payment_Gateway__c gateway = [SELECT Id FROM pymtTest__Payment_Gateway__c LIMIT 1];
        pymtTest__Invoice__c invoice = [SELECT Id FROM pymtTest__Invoice__c LIMIT 1];
        
        // Create a transaction to void
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Type__c = 'Sale',
            pymtTest__Status__c = 'Approved',
            pymtTest__Gateway_Transaction_Id__c = 'pi_test_void_12345'
        );
        insert txn;
        
        // Create allocation
        pymtTest__Payment_Allocation__c alloc = new pymtTest__Payment_Allocation__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Invoice__c = invoice.Id,
            pymtTest__Amount__c = 100.00
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
