/**
 * @description Test class for TransactionSyncBatch and TransactionSyncScheduler
 */
@isTest
private class TransactionSyncBatchTest {
    
    @TestSetup
    static void setupTestData() {
        // Create account
        Account testAccount = new Account(Name = 'Test Company');
        insert testAccount;
        
        // Create gateways
        pymts__Payment_Gateway__c stripeGateway = new pymts__Payment_Gateway__c(
            Name = 'Stripe Test',
            pymts__Gateway_Type__c = 'Stripe',
            pymts__Active__c = true,
            pymts__Is_Default__c = true,
            pymts__Environment__c = 'Test'
        );
        
        pymts__Payment_Gateway__c authNetGateway = new pymts__Payment_Gateway__c(
            Name = 'AuthNet Test',
            pymts__Gateway_Type__c = 'Authorize.Net',
            pymts__Active__c = true,
            pymts__Is_Default__c = false,
            pymts__Environment__c = 'Test'
        );
        insert new List<pymts__Payment_Gateway__c>{ stripeGateway, authNetGateway };
        
        // Create invoices
        pymts__Invoice__c invoice1 = new pymts__Invoice__c(
            pymts__Account__c = testAccount.Id,
            pymts__Total_Amount__c = 100.00,
            pymts__Amount_Paid__c = 100.00,
            pymts__Status__c = 'Paid',
            pymts__Due_Date__c = Date.today().addDays(30)
        );
        
        pymts__Invoice__c invoice2 = new pymts__Invoice__c(
            pymts__Account__c = testAccount.Id,
            pymts__Total_Amount__c = 200.00,
            pymts__Amount_Paid__c = 200.00,
            pymts__Status__c = 'Paid',
            pymts__Due_Date__c = Date.today().addDays(30)
        );
        insert new List<pymts__Invoice__c>{ invoice1, invoice2 };
        
        // Create pending settlement transactions
        pymts__Transaction__c stripeTxn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = stripeGateway.Id,
            pymts__Amount__c = 100.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved',
            pymts__Settlement_Status__c = 'Pending',
            pymts__Payment_Type__c = 'Credit Card',
            pymts__Gateway_Transaction_Id__c = 'pi_test_stripe_123'
        );
        
        pymts__Transaction__c authNetTxn = new pymts__Transaction__c(
            pymts__Account__c = testAccount.Id,
            pymts__Payment_Gateway__c = authNetGateway.Id,
            pymts__Amount__c = 200.00,
            pymts__Type__c = 'Sale',
            pymts__Status__c = 'Approved',
            pymts__Settlement_Status__c = 'Pending Settlement',
            pymts__Payment_Type__c = 'ACH',
            pymts__Gateway_Transaction_Id__c = '12345678'
        );
        insert new List<pymts__Transaction__c>{ stripeTxn, authNetTxn };
        
        // Create allocations
        pymts__Payment_Allocation__c alloc1 = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = stripeTxn.Id,
            pymts__Invoice__c = invoice1.Id,
            pymts__Amount__c = 100.00
        );
        
        pymts__Payment_Allocation__c alloc2 = new pymts__Payment_Allocation__c(
            pymts__Transaction__c = authNetTxn.Id,
            pymts__Invoice__c = invoice2.Id,
            pymts__Amount__c = 200.00
        );
        insert new List<pymts__Payment_Allocation__c>{ alloc1, alloc2 };
    }
    
    @isTest
    static void testBatchSyncStripeSettled() {
        Test.setMock(HttpCalloutMock.class, new MultiGatewayMock());
        
        Test.startTest();
        TransactionSyncBatch batch = new TransactionSyncBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify Stripe transaction was updated
        pymts__Transaction__c stripeTxn = [
            SELECT pymts__Settlement_Status__c, pymts__Last_Sync_Date__c
            FROM pymts__Transaction__c
            WHERE pymts__Gateway_Transaction_Id__c = 'pi_test_stripe_123'
        ];
        
        System.assertEquals('Settled', stripeTxn.pymts__Settlement_Status__c, 'Stripe txn should be settled');
        System.assertNotEquals(null, stripeTxn.pymts__Last_Sync_Date__c, 'Last sync date should be set');
    }
    
    @isTest
    static void testBatchSyncAuthNetSettled() {
        Test.setMock(HttpCalloutMock.class, new MultiGatewayMock());
        
        Test.startTest();
        TransactionSyncBatch batch = new TransactionSyncBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify AuthNet transaction was updated
        pymts__Transaction__c authNetTxn = [
            SELECT pymts__Settlement_Status__c, pymts__Settlement_Date__c
            FROM pymts__Transaction__c
            WHERE pymts__Gateway_Transaction_Id__c = '12345678'
        ];
        
        System.assertEquals('Settled', authNetTxn.pymts__Settlement_Status__c, 'AuthNet txn should be settled');
    }
    
    @isTest
    static void testBatchSyncACHReturn() {
        // Update transaction to simulate ACH waiting for settlement
        pymts__Transaction__c achTxn = [
            SELECT Id FROM pymts__Transaction__c 
            WHERE pymts__Payment_Type__c = 'ACH'
        ];
        achTxn.pymts__Settlement_Status__c = 'Settled';
        update achTxn;
        
        Test.setMock(HttpCalloutMock.class, new ACHReturnMock());
        
        Test.startTest();
        TransactionSyncBatch batch = new TransactionSyncBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify transaction was marked as returned
        achTxn = [
            SELECT pymts__Status__c, pymts__Settlement_Status__c, pymts__Return_Reason_Code__c
            FROM pymts__Transaction__c
            WHERE Id = :achTxn.Id
        ];
        
        System.assertEquals('Returned', achTxn.pymts__Settlement_Status__c, 'Should be marked as returned');
        System.assertEquals('R01', achTxn.pymts__Return_Reason_Code__c, 'Return code should be R01');
        
        // Verify invoice was reversed
        pymts__Invoice__c invoice = [
            SELECT pymts__Amount_Paid__c, pymts__Status__c
            FROM pymts__Invoice__c
            WHERE pymts__Total_Amount__c = 200.00
        ];
        
        System.assertEquals(0, invoice.pymts__Amount_Paid__c, 'Invoice payment should be reversed');
        System.assertEquals('Pending', invoice.pymts__Status__c, 'Invoice status should be Pending');
    }
    
    @isTest
    static void testBatchSyncSpecificGateway() {
        pymts__Payment_Gateway__c stripeGateway = [
            SELECT Id FROM pymts__Payment_Gateway__c WHERE pymts__Gateway_Type__c = 'Stripe'
        ];
        
        Test.setMock(HttpCalloutMock.class, new MultiGatewayMock());
        
        Test.startTest();
        TransactionSyncBatch batch = new TransactionSyncBatch(stripeGateway.Id);
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify only Stripe transaction was processed
        pymts__Transaction__c stripeTxn = [
            SELECT pymts__Settlement_Status__c
            FROM pymts__Transaction__c
            WHERE pymts__Gateway_Transaction_Id__c = 'pi_test_stripe_123'
        ];
        
        System.assertEquals('Settled', stripeTxn.pymts__Settlement_Status__c, 'Stripe txn should be settled');
    }
    
    @isTest
    static void testSchedulerEveryFourHours() {
        Test.startTest();
        TransactionSyncScheduler.scheduleEveryFourHours();
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'Transaction Sync%'
        ];
        
        System.assertEquals(6, jobs.size(), 'Should schedule 6 jobs (every 4 hours)');
    }
    
    @isTest
    static void testSchedulerTwiceDaily() {
        Test.startTest();
        TransactionSyncScheduler.scheduleTwiceDaily();
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'Transaction Sync%'
        ];
        
        System.assertEquals(2, jobs.size(), 'Should schedule 2 jobs');
    }
    
    @isTest
    static void testSchedulerUnschedule() {
        TransactionSyncScheduler.scheduleTwiceDaily();
        
        Test.startTest();
        TransactionSyncScheduler.unscheduleAll();
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'Transaction Sync%'
        ];
        
        System.assertEquals(0, jobs.size(), 'All jobs should be unscheduled');
    }
    
    @isTest
    static void testSchedulerExecute() {
        Test.setMock(HttpCalloutMock.class, new MultiGatewayMock());
        
        Test.startTest();
        TransactionSyncScheduler scheduler = new TransactionSyncScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        // Verify batch was started
        List<AsyncApexJob> jobs = [
            SELECT Id, Status FROM AsyncApexJob 
            WHERE ApexClass.Name = 'TransactionSyncBatch'
        ];
        
        System.assert(!jobs.isEmpty(), 'Batch job should be created');
    }
    
    @isTest
    static void testRunNow() {
        Test.setMock(HttpCalloutMock.class, new MultiGatewayMock());
        
        Test.startTest();
        Id batchId = TransactionSyncScheduler.runNow();
        Test.stopTest();
        
        System.assertNotEquals(null, batchId, 'Should return batch job ID');
    }
    
    @isTest
    static void testGetACHReturnDescription() {
        System.assertEquals('Insufficient Funds', 
            TransactionSyncBatch.getACHReturnDescription('R01'), 
            'R01 should be Insufficient Funds');
        System.assertEquals('Account Closed', 
            TransactionSyncBatch.getACHReturnDescription('R02'), 
            'R02 should be Account Closed');
        System.assertEquals('Unknown return reason', 
            TransactionSyncBatch.getACHReturnDescription('RXXX'), 
            'Unknown code should return default message');
    }
    
    @isTest
    static void testAuditLogCreation() {
        Test.setMock(HttpCalloutMock.class, new MultiGatewayMock());
        
        Test.startTest();
        TransactionSyncBatch batch = new TransactionSyncBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify audit logs were created
        List<pymts__Audit_Log__c> logs = [
            SELECT pymts__Action__c, pymts__Details__c 
            FROM pymts__Audit_Log__c
        ];
        
        // At least one audit log should be created for settled transactions
        System.assert(logs.size() > 0, 'Audit logs should be created');
    }
    
    // ==================== Mock Classes ====================
    
    private class MultiGatewayMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('stripe.com')) {
                // Stripe response
                res.setBody('{"id":"pi_test_stripe_123","status":"succeeded","captured":true}');
            } else if (endpoint.contains('authorize.net')) {
                // Authorize.Net response
                res.setBody('{"transaction":{"transId":"12345678","transactionStatus":"settledSuccessfully","settlementState":"settledSuccessfully","settleAmount":200.00,"batch":{"batchId":"batch123","settlementTimeUTC":"2024-01-15T18:00:00Z"}},"messages":{"resultCode":"Ok"}}');
            }
            
            return res;
        }
    }
    
    private class ACHReturnMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            
            // Return ACH return response
            res.setBody('{"transaction":{"transId":"12345678","transactionStatus":"returned","returnedItems":[{"code":"R01","description":"Insufficient Funds"}]},"messages":{"resultCode":"Ok"}}');
            
            return res;
        }
    }
}
