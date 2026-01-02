/**
 * @description Test class for InvoiceService
 */
@isTest
private class InvoiceServiceTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account testAccount = new Account(Name = 'Test Company');
        insert testAccount;
        
        // Create test gateway
        pymts__Payment_Gateway__c gateway = new pymts__Payment_Gateway__c(
            Name = 'Test Gateway',
            pymts__Gateway_Type__c = 'Stripe',
            pymts__Active__c = true,
            pymts__Is_Default__c = true,
            pymts__Environment__c = 'Test'
        );
        insert gateway;
        
        // Create test product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            IsActive = true,
            pymts__Is_Recurring__c = false
        );
        insert testProduct;
        
        // Create recurring product
        Product2 recurringProduct = new Product2(
            Name = 'Recurring Service',
            IsActive = true,
            pymts__Is_Recurring__c = true
        );
        insert recurringProduct;
        
        // Create pricebook entry
        Id stdPricebookId = Test.getStandardPricebookId();
        
        PricebookEntry pbe1 = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100.00,
            IsActive = true
        );
        insert pbe1;
        
        PricebookEntry pbe2 = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = recurringProduct.Id,
            UnitPrice = 50.00,
            IsActive = true
        );
        insert pbe2;
    }
    
    @isTest
    static void testGenerateInvoicesOneTime() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        Product2 testProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Product' LIMIT 1];
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :testProduct.Id LIMIT 1];
        
        // Create one-time order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            EndDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPricebookId,
            pymts__Payment_Frequency__c = 'One-Time'
        );
        insert testOrder;
        
        // Add order product
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = testProduct.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            UnitPrice = 100.00
        );
        insert oi;
        
        // Activate order
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.startTest();
        List<Id> invoiceIds = InvoiceService.generateInvoicesFromOrder(testOrder.Id);
        Test.stopTest();
        
        System.assertEquals(1, invoiceIds.size(), 'Should create 1 invoice for one-time order');
        
        pymts__Invoice__c invoice = [
            SELECT pymts__Total_Amount__c, pymts__Status__c 
            FROM pymts__Invoice__c 
            WHERE Id = :invoiceIds[0]
        ];
        System.assertEquals(200.00, invoice.pymts__Total_Amount__c, 'Invoice total should be 200');
        System.assertEquals('Pending', invoice.pymts__Status__c, 'Status should be Pending');
    }
    
    @isTest
    static void testGenerateInvoicesMonthly() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        Product2 recurringProduct = [SELECT Id FROM Product2 WHERE Name = 'Recurring Service' LIMIT 1];
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :recurringProduct.Id LIMIT 1];
        
        // Create monthly order for 3 months
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            EndDate = Date.today().addMonths(3),
            Status = 'Draft',
            Pricebook2Id = stdPricebookId,
            pymts__Payment_Frequency__c = 'Monthly'
        );
        insert testOrder;
        
        // Add recurring product
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = recurringProduct.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 50.00
        );
        insert oi;
        
        // Activate order
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.startTest();
        List<Id> invoiceIds = InvoiceService.generateInvoicesFromOrder(testOrder.Id);
        Test.stopTest();
        
        System.assertEquals(3, invoiceIds.size(), 'Should create 3 invoices for 3-month subscription');
        
        List<pymts__Invoice__c> invoices = [
            SELECT pymts__Total_Amount__c, pymts__Invoice_Date__c 
            FROM pymts__Invoice__c 
            WHERE Id IN :invoiceIds
            ORDER BY pymts__Invoice_Date__c ASC
        ];
        
        for (pymts__Invoice__c inv : invoices) {
            System.assertEquals(50.00, inv.pymts__Total_Amount__c, 'Each invoice should be 50');
        }
    }
    
    @isTest
    static void testGenerateInvoicesQuarterly() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        Product2 recurringProduct = [SELECT Id FROM Product2 WHERE Name = 'Recurring Service' LIMIT 1];
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :recurringProduct.Id LIMIT 1];
        
        // Create quarterly order for 1 year
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            EndDate = Date.today().addMonths(12),
            Status = 'Draft',
            Pricebook2Id = stdPricebookId,
            pymts__Payment_Frequency__c = 'Quarterly'
        );
        insert testOrder;
        
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = recurringProduct.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 150.00
        );
        insert oi;
        
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.startTest();
        List<Id> invoiceIds = InvoiceService.generateInvoicesFromOrder(testOrder.Id);
        Test.stopTest();
        
        System.assertEquals(4, invoiceIds.size(), 'Should create 4 quarterly invoices for 1 year');
    }
    
    @isTest
    static void testGenerateInvoicesAnnual() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        Product2 recurringProduct = [SELECT Id FROM Product2 WHERE Name = 'Recurring Service' LIMIT 1];
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Product2Id = :recurringProduct.Id LIMIT 1];
        
        // Create annual order for 2 years
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            EndDate = Date.today().addYears(2),
            Status = 'Draft',
            Pricebook2Id = stdPricebookId,
            pymts__Payment_Frequency__c = 'Annual'
        );
        insert testOrder;
        
        OrderItem oi = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = recurringProduct.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 500.00
        );
        insert oi;
        
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.startTest();
        List<Id> invoiceIds = InvoiceService.generateInvoicesFromOrder(testOrder.Id);
        Test.stopTest();
        
        System.assertEquals(2, invoiceIds.size(), 'Should create 2 annual invoices');
    }
    
    @isTest
    static void testGetInvoiceDetails() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        // Create invoice
        pymts__Invoice__c invoice = new pymts__Invoice__c(
            pymts__Account__c = testAccount.Id,
            pymts__Total_Amount__c = 250.00,
            pymts__Amount_Paid__c = 100.00,
            pymts__Status__c = 'Partially Paid',
            pymts__Due_Date__c = Date.today().addDays(30),
            pymts__Payment_Gateway__c = gateway.Id
        );
        insert invoice;
        
        // Create line items
        List<pymts__Invoice_Line_Item__c> lineItems = new List<pymts__Invoice_Line_Item__c>{
            new pymts__Invoice_Line_Item__c(
                pymts__Invoice__c = invoice.Id,
                pymts__Description__c = 'Product A',
                pymts__Quantity__c = 2,
                pymts__Unit_Price__c = 75.00
            ),
            new pymts__Invoice_Line_Item__c(
                pymts__Invoice__c = invoice.Id,
                pymts__Description__c = 'Product B',
                pymts__Quantity__c = 1,
                pymts__Unit_Price__c = 100.00
            )
        };
        insert lineItems;
        
        // Create transaction
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 100.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved'
        );
        insert txn;
        
        // Create allocation
        pymts__Payment_Allocation__c alloc = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = txn.Id,
            pymts__Invoice__c = invoice.Id,
            pymts__Amount__c = 100.00
        );
        insert alloc;
        
        Test.startTest();
        InvoiceService.InvoiceDetailWrapper details = InvoiceService.getInvoiceDetails(invoice.Id);
        Test.stopTest();
        
        System.assertEquals(250.00, details.totalAmount, 'Total should be 250');
        System.assertEquals(100.00, details.amountPaid, 'Amount paid should be 100');
        System.assertEquals(150.00, details.balanceDue, 'Balance due should be 150');
        System.assertEquals(2, details.lineItems.size(), 'Should have 2 line items');
        System.assertEquals(1, details.payments.size(), 'Should have 1 payment');
    }
    
    @isTest
    static void testUpdateAllocations() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        pymts__Payment_Gateway__c gateway = [SELECT Id FROM pymts__Payment_Gateway__c LIMIT 1];
        
        // Create invoices
        List<pymts__Invoice__c> invoices = new List<pymts__Invoice__c>();
        for (Integer i = 0; i < 2; i++) {
            invoices.add(new pymts__Invoice__c(
                pymts__Account__c = testAccount.Id,
                pymts__Total_Amount__c = 100.00,
                pymts__Amount_Paid__c = 0,
                pymts__Status__c = 'Pending',
                pymts__Due_Date__c = Date.today().addDays(30)
            ));
        }
        insert invoices;
        
        // Create transaction
        pymts__Transaction__c txn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = gateway.Id,
            pymts__Amount__c = 150.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved'
        );
        insert txn;
        
        // Create initial allocation (all to first invoice)
        pymts__Payment_Allocation__c alloc = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = txn.Id,
            pymts__Invoice__c = invoices[0].Id,
            pymts__Amount__c = 150.00
        );
        insert alloc;
        
        invoices[0].pymts__Amount_Paid__c = 150.00;
        update invoices[0];
        
        // Prepare new allocations (split between both invoices)
        List<InvoiceService.AllocationUpdate> updates = new List<InvoiceService.AllocationUpdate>();
        
        InvoiceService.AllocationUpdate update1 = new InvoiceService.AllocationUpdate();
        update1.invoiceId = invoices[0].Id;
        update1.amount = 100.00;
        updates.add(update1);
        
        InvoiceService.AllocationUpdate update2 = new InvoiceService.AllocationUpdate();
        update2.invoiceId = invoices[1].Id;
        update2.amount = 50.00;
        updates.add(update2);
        
        Test.startTest();
        InvoiceService.updateAllocations(txn.Id, updates);
        Test.stopTest();
        
        // Verify allocations
        List<pymts__Payment_Allocation__c> newAllocs = [
            SELECT pymts__Invoice__c, pymts__Amount__c 
            FROM pymts__Payment_Allocation__c 
            WHERE pymts__Transaction__c = :txn.Id
            ORDER BY pymts__Amount__c DESC
        ];
        
        System.assertEquals(2, newAllocs.size(), 'Should have 2 allocations');
        System.assertEquals(100.00, newAllocs[0].pymts__Amount__c, 'First allocation should be 100');
        System.assertEquals(50.00, newAllocs[1].pymts__Amount__c, 'Second allocation should be 50');
    }
    
    @isTest
    static void testMixedProducts() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Company' LIMIT 1];
        Product2 oneTimeProduct = [SELECT Id FROM Product2 WHERE Name = 'Test Product' LIMIT 1];
        Product2 recurringProduct = [SELECT Id FROM Product2 WHERE Name = 'Recurring Service' LIMIT 1];
        Id stdPricebookId = Test.getStandardPricebookId();
        PricebookEntry pbe1 = [SELECT Id FROM PricebookEntry WHERE Product2Id = :oneTimeProduct.Id LIMIT 1];
        PricebookEntry pbe2 = [SELECT Id FROM PricebookEntry WHERE Product2Id = :recurringProduct.Id LIMIT 1];
        
        // Create order with both product types
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            EffectiveDate = Date.today(),
            EndDate = Date.today().addMonths(3),
            Status = 'Draft',
            Pricebook2Id = stdPricebookId,
            pymts__Payment_Frequency__c = 'Monthly'
        );
        insert testOrder;
        
        // One-time product
        OrderItem oi1 = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = oneTimeProduct.Id,
            PricebookEntryId = pbe1.Id,
            Quantity = 1,
            UnitPrice = 200.00
        );
        
        // Recurring product
        OrderItem oi2 = new OrderItem(
            OrderId = testOrder.Id,
            Product2Id = recurringProduct.Id,
            PricebookEntryId = pbe2.Id,
            Quantity = 1,
            UnitPrice = 30.00
        );
        insert new List<OrderItem>{ oi1, oi2 };
        
        testOrder.Status = 'Activated';
        update testOrder;
        
        Test.startTest();
        List<Id> invoiceIds = InvoiceService.generateInvoicesFromOrder(testOrder.Id);
        Test.stopTest();
        
        // Should create 3 invoices: first has one-time + recurring, others have just recurring
        System.assertEquals(3, invoiceIds.size(), 'Should create 3 invoices');
        
        List<pymts__Invoice__c> invoices = [
            SELECT pymts__Total_Amount__c 
            FROM pymts__Invoice__c 
            WHERE Id IN :invoiceIds
            ORDER BY pymts__Invoice_Date__c ASC
        ];
        
        // First invoice: 200 (one-time) + 30 (recurring) = 230
        System.assertEquals(230.00, invoices[0].pymts__Total_Amount__c, 'First invoice should include one-time product');
        
        // Subsequent invoices: just recurring
        System.assertEquals(30.00, invoices[1].pymts__Total_Amount__c, 'Second invoice should only have recurring');
        System.assertEquals(30.00, invoices[2].pymts__Total_Amount__c, 'Third invoice should only have recurring');
    }
}
