/**
 * @description Test class for OrderFulfillmentQueueable
 */
@isTest
private class OrderFulfillmentQueueableTest {
    
    @TestSetup
    static void setupTestData() {
        // Create test account
        Account acc = new Account(Name = 'Fulfillment Test Account', Phone = '555-1234');
        insert acc;
        
        // Create test products
        List<Product2> products = new List<Product2>();
        products.add(new Product2(Name = 'Test Product A', ProductCode = 'PROD-A', IsActive = true));
        products.add(new Product2(Name = 'Test Product B', ProductCode = 'PROD-B', IsActive = true));
        insert products;
        
        // Create pricebook entries
        Id standardPbId = Test.getStandardPricebookId();
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        pbes.add(new PricebookEntry(Pricebook2Id = standardPbId, Product2Id = products[0].Id, UnitPrice = 100.00, IsActive = true));
        pbes.add(new PricebookEntry(Pricebook2Id = standardPbId, Product2Id = products[1].Id, UnitPrice = 50.00, IsActive = true));
        insert pbes;
        
        // Create payment gateway
        pymtTest__Payment_Gateway__c gateway = new pymtTest__Payment_Gateway__c(
            Name = 'Test Gateway',
            pymtTest__Gateway_Type__c = 'Stripe',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test'
        );
        insert gateway;
        
        // Create custom notification type (if it doesn't exist)
        // Note: This is typically done via metadata deployment
    }
    
    @isTest
    static void testSuccessfulFulfillment() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        List<Product2> products = [SELECT Id FROM Product2 ORDER BY Name];
        
        // Create transaction
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = acc.Id,
            pymtTest__Amount__c = 200.00,
            pymtTest__Status__c = 'Completed',
            pymtTest__Type__c = 'Sale',
            pymtTest__Sales_Channel__c = 'Phone',
            pymtTest__Fulfillment_Status__c = 'Pending',
            pymtTest__Gateway_Transaction_Id__c = 'test_txn_123'
        );
        insert txn;
        
        // Create line items
        List<pymtTest__Transaction_Line_Item__c> lineItems = new List<pymtTest__Transaction_Line_Item__c>();
        lineItems.add(new pymtTest__Transaction_Line_Item__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Product__c = products[0].Id,
            pymtTest__Quantity__c = 1,
            pymtTest__Unit_Price__c = 100.00
        ));
        lineItems.add(new pymtTest__Transaction_Line_Item__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Product__c = products[1].Id,
            pymtTest__Quantity__c = 2,
            pymtTest__Unit_Price__c = 50.00
        ));
        insert lineItems;
        
        Test.startTest();
        System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
        Test.stopTest();
        
        // Verify transaction was updated
        pymtTest__Transaction__c updatedTxn = [
            SELECT pymtTest__Fulfillment_Status__c, pymtTest__Order__c
            FROM pymtTest__Transaction__c
            WHERE Id = :txn.Id
        ];
        System.assertEquals('Complete', updatedTxn.pymtTest__Fulfillment_Status__c, 'Fulfillment should be complete');
        System.assertNotEquals(null, updatedTxn.pymtTest__Order__c, 'Order should be linked');
        
        // Verify Order was created
        Order createdOrder = [SELECT Id, Status, AccountId FROM Order WHERE Id = :updatedTxn.pymtTest__Order__c];
        System.assertEquals('Activated', createdOrder.Status, 'Order should be activated');
        System.assertEquals(acc.Id, createdOrder.AccountId, 'Order should be linked to account');
        
        // Verify Order Items were created
        List<OrderItem> orderItems = [SELECT Id, Quantity, UnitPrice FROM OrderItem WHERE OrderId = :createdOrder.Id];
        System.assertEquals(2, orderItems.size(), 'Should have 2 order items');
        
        // Verify Invoice was created
        List<pymtTest__Invoice__c> invoices = [
            SELECT pymtTest__Status__c, pymtTest__Total_Amount__c, pymtTest__Amount_Paid__c
            FROM pymtTest__Invoice__c
            WHERE pymtTest__Order__c = :createdOrder.Id
        ];
        System.assertEquals(1, invoices.size(), 'Should have 1 invoice');
        System.assertEquals('Paid', invoices[0].pymtTest__Status__c, 'Invoice should be Paid');
        System.assertEquals(200.00, invoices[0].pymtTest__Total_Amount__c, 'Invoice total should match');
        
        // Verify Invoice Line Items
        List<pymtTest__Invoice_Line_Item__c> invoiceLines = [
            SELECT Id FROM pymtTest__Invoice_Line_Item__c WHERE pymtTest__Invoice__c = :invoices[0].Id
        ];
        System.assertEquals(2, invoiceLines.size(), 'Should have 2 invoice line items');
        
        // Verify Payment Allocation
        List<pymtTest__Payment_Allocation__c> allocations = [
            SELECT pymtTest__Amount__c FROM pymtTest__Payment_Allocation__c WHERE pymtTest__Transaction__c = :txn.Id
        ];
        System.assertEquals(1, allocations.size(), 'Should have 1 allocation');
        System.assertEquals(200.00, allocations[0].pymtTest__Amount__c, 'Allocation amount should match');
        
        // Verify Transaction Line Items were updated with Order Product references
        List<pymtTest__Transaction_Line_Item__c> updatedLineItems = [
            SELECT pymtTest__Order_Product__c FROM pymtTest__Transaction_Line_Item__c WHERE pymtTest__Transaction__c = :txn.Id
        ];
        for (pymtTest__Transaction_Line_Item__c li : updatedLineItems) {
            System.assertNotEquals(null, li.pymtTest__Order_Product__c, 'Line item should be linked to order product');
        }
    }
    
    @isTest
    static void testFulfillmentWithSingleItem() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        
        // Create transaction with single item
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = acc.Id,
            pymtTest__Amount__c = 500.00,
            pymtTest__Status__c = 'Completed',
            pymtTest__Type__c = 'Sale',
            pymtTest__Sales_Channel__c = 'Phone',
            pymtTest__Fulfillment_Status__c = 'Pending'
        );
        insert txn;
        
        pymtTest__Transaction_Line_Item__c lineItem = new pymtTest__Transaction_Line_Item__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Product__c = product.Id,
            pymtTest__Quantity__c = 5,
            pymtTest__Unit_Price__c = 100.00,
            pymtTest__Description__c = 'Bulk order'
        );
        insert lineItem;
        
        Test.startTest();
        System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
        Test.stopTest();
        
        pymtTest__Transaction__c result = [SELECT pymtTest__Fulfillment_Status__c FROM pymtTest__Transaction__c WHERE Id = :txn.Id];
        System.assertEquals('Complete', result.pymtTest__Fulfillment_Status__c);
        
        // Verify single order item with correct quantity
        pymtTest__Transaction__c txnWithOrder = [SELECT pymtTest__Order__c FROM pymtTest__Transaction__c WHERE Id = :txn.Id];
        OrderItem oi = [SELECT Quantity, Description FROM OrderItem WHERE OrderId = :txnWithOrder.pymtTest__Order__c];
        System.assertEquals(5, oi.Quantity, 'Order item quantity should be 5');
        System.assertEquals('Bulk order', oi.Description, 'Description should be carried over');
    }
    
    @isTest
    static void testFulfillmentFailure_NoLineItems() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create transaction WITHOUT line items
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = acc.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Status__c = 'Completed',
            pymtTest__Type__c = 'Sale',
            pymtTest__Sales_Channel__c = 'Phone',
            pymtTest__Fulfillment_Status__c = 'Pending'
        );
        insert txn;
        
        Test.startTest();
        System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
        Test.stopTest();
        
        pymtTest__Transaction__c result = [
            SELECT pymtTest__Fulfillment_Status__c, pymtTest__Fulfillment_Error__c
            FROM pymtTest__Transaction__c 
            WHERE Id = :txn.Id
        ];
        System.assertEquals('Failed', result.pymtTest__Fulfillment_Status__c, 'Should fail without line items');
        System.assert(result.pymtTest__Fulfillment_Error__c.contains('No line items'), 'Error should mention line items');
    }
    
    @isTest
    static void testAuditLogCreation() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Product2 product = [SELECT Id FROM Product2 LIMIT 1];
        
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = acc.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Status__c = 'Completed',
            pymtTest__Sales_Channel__c = 'Phone',
            pymtTest__Fulfillment_Status__c = 'Pending'
        );
        insert txn;
        
        pymtTest__Transaction_Line_Item__c lineItem = new pymtTest__Transaction_Line_Item__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Product__c = product.Id,
            pymtTest__Quantity__c = 1,
            pymtTest__Unit_Price__c = 100.00
        );
        insert lineItem;
        
        Test.startTest();
        System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
        Test.stopTest();
        
        // Verify audit log was created
        List<pymtTest__Audit_Log__c> logs = [
            SELECT pymtTest__Action__c, pymtTest__Details__c
            FROM pymtTest__Audit_Log__c
            WHERE pymtTest__Transaction__c = :txn.Id
        ];
        System.assertEquals(1, logs.size(), 'Should have audit log');
        System.assertEquals('Fulfillment Complete', logs[0].pymtTest__Action__c);
    }
    
    @isTest
    static void testTaskCreationOnFailure() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        
        // Create transaction without line items to trigger failure
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = acc.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Status__c = 'Completed',
            pymtTest__Sales_Channel__c = 'Phone',
            pymtTest__Fulfillment_Status__c = 'Pending'
        );
        insert txn;
        
        Test.startTest();
        System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
        Test.stopTest();
        
        // Verify task was created
        List<Task> tasks = [
            SELECT Subject, Priority, Status
            FROM Task
            WHERE WhatId = :txn.Id
        ];
        System.assertEquals(1, tasks.size(), 'Should have follow-up task');
        System.assert(tasks[0].Subject.contains('Failed Order Fulfillment'), 'Task subject should indicate failure');
        System.assertEquals('High', tasks[0].Priority, 'Task should be high priority');
    }
    
    @isTest
    static void testRollbackOnPartialFailure() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        // Use a product that doesn't have a pricebook entry
        Product2 newProduct = new Product2(Name = 'No Price Product', IsActive = true);
        insert newProduct;
        // Don't create pricebook entry for this product
        
        pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
            pymtTest__Account__c = acc.Id,
            pymtTest__Amount__c = 100.00,
            pymtTest__Status__c = 'Completed',
            pymtTest__Sales_Channel__c = 'Phone',
            pymtTest__Fulfillment_Status__c = 'Pending'
        );
        insert txn;
        
        pymtTest__Transaction_Line_Item__c lineItem = new pymtTest__Transaction_Line_Item__c(
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Product__c = newProduct.Id,
            pymtTest__Quantity__c = 1,
            pymtTest__Unit_Price__c = 100.00
        );
        insert lineItem;
        
        Test.startTest();
        System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
        Test.stopTest();
        
        // Verify no Order was created (rolled back)
        List<Order> orders = [SELECT Id FROM Order WHERE AccountId = :acc.Id];
        System.assertEquals(0, orders.size(), 'Order should be rolled back');
        
        // Verify transaction shows failure
        pymtTest__Transaction__c result = [SELECT pymtTest__Fulfillment_Status__c FROM pymtTest__Transaction__c WHERE Id = :txn.Id];
        System.assertEquals('Failed', result.pymtTest__Fulfillment_Status__c);
    }
}
