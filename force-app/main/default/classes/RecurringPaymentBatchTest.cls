/**
 * @description Test class for RecurringPaymentBatch and RecurringPaymentScheduler
 */
@isTest
private class RecurringPaymentBatchTest {
    
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
        
        // Create payment method
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
        
        // Create auto-pay invoices scheduled for today
        List<pymtTest__Invoice__c> invoices = new List<pymtTest__Invoice__c>();
        
        // Invoice 1: Due today, auto-pay enabled
        invoices.add(new pymtTest__Invoice__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Total_Amount__c = 100.00,
            pymtTest__Amount_Paid__c = 0,
            pymtTest__Status__c = 'Scheduled',
            pymtTest__Due_Date__c = Date.today(),
            pymtTest__Scheduled_Payment_Date__c = Date.today(),
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Auto_Pay__c = true,
            pymtTest__Retry_Count__c = 0
        ));
        
        // Invoice 2: Scheduled for today
        invoices.add(new pymtTest__Invoice__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Total_Amount__c = 200.00,
            pymtTest__Amount_Paid__c = 0,
            pymtTest__Status__c = 'Scheduled',
            pymtTest__Due_Date__c = Date.today(),
            pymtTest__Scheduled_Payment_Date__c = Date.today(),
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Auto_Pay__c = true,
            pymtTest__Retry_Count__c = 0
        ));
        
        // Invoice 3: Scheduled for future (should not be processed)
        invoices.add(new pymtTest__Invoice__c(
            pymtTest__Account__c = testAccount.Id,
            pymtTest__Total_Amount__c = 150.00,
            pymtTest__Amount_Paid__c = 0,
            pymtTest__Status__c = 'Scheduled',
            pymtTest__Due_Date__c = Date.today().addDays(7),
            pymtTest__Scheduled_Payment_Date__c = Date.today().addDays(7),
            pymtTest__Payment_Gateway__c = gateway.Id,
            pymtTest__Auto_Pay__c = true,
            pymtTest__Retry_Count__c = 0
        ));
        
        insert invoices;
        
        // Create line items
        List<pymtTest__Invoice_Line_Item__c> lineItems = new List<pymtTest__Invoice_Line_Item__c>();
        for (pymtTest__Invoice__c inv : invoices) {
            lineItems.add(new pymtTest__Invoice_Line_Item__c(
                pymtTest__Invoice__c = inv.Id,
                pymtTest__Description__c = 'Monthly Service',
                pymtTest__Quantity__c = 1,
                pymtTest__Unit_Price__c = inv.pymtTest__Total_Amount__c
            ));
        }
        insert lineItems;
    }
    
    @isTest
    static void testBatchProcessPaymentsSuccess() {
        Test.setMock(HttpCalloutMock.class, new PaymentSuccessMock());
        
        Test.startTest();
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify invoices were paid
        List<pymtTest__Invoice__c> paidInvoices = [
            SELECT pymtTest__Status__c, pymtTest__Amount_Paid__c
            FROM pymtTest__Invoice__c
            WHERE pymtTest__Scheduled_Payment_Date__c = TODAY
        ];
        
        for (pymtTest__Invoice__c inv : paidInvoices) {
            System.assertEquals('Paid', inv.pymtTest__Status__c, 'Invoice should be paid');
        }
        
        // Verify transactions were created
        List<pymtTest__Transaction__c> txns = [
            SELECT pymtTest__Amount__c, pymtTest__Status__c
            FROM pymtTest__Transaction__c
        ];
        
        System.assertEquals(2, txns.size(), 'Should create 2 transactions');
        
        for (pymtTest__Transaction__c txn : txns) {
            System.assertEquals('Approved', txn.pymtTest__Status__c, 'Transaction should be approved');
        }
    }
    
    @isTest
    static void testBatchProcessPaymentsFailed() {
        Test.setMock(HttpCalloutMock.class, new PaymentFailedMock());
        
        Test.startTest();
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify retry count was incremented
        List<pymtTest__Invoice__c> invoices = [
            SELECT pymtTest__Status__c, pymtTest__Retry_Count__c
            FROM pymtTest__Invoice__c
            WHERE pymtTest__Scheduled_Payment_Date__c = TODAY
        ];
        
        for (pymtTest__Invoice__c inv : invoices) {
            System.assertEquals(1, inv.pymtTest__Retry_Count__c, 'Retry count should be incremented');
        }
        
        // Verify retry logs were created
        List<pymtTest__Retry_Log__c> logs = [
            SELECT pymtTest__Status__c, pymtTest__Message__c
            FROM pymtTest__Retry_Log__c
        ];
        
        System.assertEquals(2, logs.size(), 'Should create 2 retry logs');
        
        for (pymtTest__Retry_Log__c log : logs) {
            System.assertEquals('Failed', log.pymtTest__Status__c, 'Log status should be Failed');
        }
    }
    
    @isTest
    static void testBatchSkipsMaxRetries() {
        // Update invoice to max retries
        pymtTest__Invoice__c invoice = [
            SELECT Id FROM pymtTest__Invoice__c 
            WHERE pymtTest__Total_Amount__c = 100.00
        ];
        invoice.pymtTest__Retry_Count__c = 3; // Default max
        update invoice;
        
        Test.setMock(HttpCalloutMock.class, new PaymentSuccessMock());
        
        Test.startTest();
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify max retry invoice was not processed (no new transaction)
        List<pymtTest__Transaction__c> txns = [
            SELECT pymtTest__Amount__c FROM pymtTest__Transaction__c
        ];
        
        // Only 1 transaction for the other invoice
        System.assertEquals(1, txns.size(), 'Should only process 1 invoice');
        System.assertEquals(200.00, txns[0].pymtTest__Amount__c, 'Should process the 200 invoice');
    }
    
    @isTest
    static void testBatchSkipsExpiredCard() {
        // Update payment method to be expired
        pymtTest__Payment_Method__c pm = [SELECT Id FROM pymtTest__Payment_Method__c LIMIT 1];
        pm.pymtTest__Expiration_Month__c = 1;
        pm.pymtTest__Expiration_Year__c = Date.today().year() - 1;
        update pm;
        
        Test.setMock(HttpCalloutMock.class, new PaymentSuccessMock());
        
        Test.startTest();
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify no transactions were created (card expired)
        List<pymtTest__Transaction__c> txns = [SELECT Id FROM pymtTest__Transaction__c];
        System.assertEquals(0, txns.size(), 'Should not process with expired card');
    }
    
    @isTest
    static void testBatchSkipsNoPrimaryPaymentMethod() {
        // Remove primary flag
        pymtTest__Payment_Method__c pm = [SELECT Id FROM pymtTest__Payment_Method__c LIMIT 1];
        pm.pymtTest__Is_Primary__c = false;
        update pm;
        
        Test.setMock(HttpCalloutMock.class, new PaymentSuccessMock());
        
        Test.startTest();
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // Verify no transactions were created
        List<pymtTest__Transaction__c> txns = [SELECT Id FROM pymtTest__Transaction__c];
        System.assertEquals(0, txns.size(), 'Should not process without primary payment method');
    }
    
    @isTest
    static void testSchedulerDaily() {
        Test.startTest();
        RecurringPaymentScheduler.scheduleDaily(6);
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT CronExpression FROM CronTrigger 
            WHERE CronJobDetail.Name = 'Recurring Payment Batch - Daily'
        ];
        
        System.assertEquals(1, jobs.size(), 'Should schedule 1 job');
        System.assert(jobs[0].CronExpression.contains('6'), 'Should run at hour 6');
    }
    
    @isTest
    static void testSchedulerUnschedule() {
        RecurringPaymentScheduler.scheduleDaily(6);
        
        Test.startTest();
        RecurringPaymentScheduler.unschedule();
        Test.stopTest();
        
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'Recurring Payment%'
        ];
        
        System.assertEquals(0, jobs.size(), 'Job should be unscheduled');
    }
    
    @isTest
    static void testSchedulerExecute() {
        Test.setMock(HttpCalloutMock.class, new PaymentSuccessMock());
        
        Test.startTest();
        RecurringPaymentScheduler scheduler = new RecurringPaymentScheduler();
        scheduler.execute(null);
        Test.stopTest();
        
        // Verify batch was started
        List<AsyncApexJob> jobs = [
            SELECT Id FROM AsyncApexJob 
            WHERE ApexClass.Name = 'RecurringPaymentBatch'
        ];
        
        System.assert(!jobs.isEmpty(), 'Batch job should be created');
    }
    
    @isTest
    static void testExponentialBackoff() {
        // First failure - should schedule for tomorrow
        pymtTest__Invoice__c invoice = [
            SELECT Id, pymtTest__Retry_Count__c, pymtTest__Scheduled_Payment_Date__c
            FROM pymtTest__Invoice__c 
            WHERE pymtTest__Total_Amount__c = 100.00
        ];
        
        Test.setMock(HttpCalloutMock.class, new PaymentFailedMock());
        
        Test.startTest();
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();
        
        // After first failure, check retry date
        invoice = [
            SELECT pymtTest__Retry_Count__c, pymtTest__Scheduled_Payment_Date__c
            FROM pymtTest__Invoice__c 
            WHERE Id = :invoice.Id
        ];
        
        System.assertEquals(1, invoice.pymtTest__Retry_Count__c, 'Retry count should be 1');
        // Next retry should be 1 day later (2^0 = 1)
        System.assertEquals(Date.today().addDays(1), invoice.pymtTest__Scheduled_Payment_Date__c, 
            'Next retry should be tomorrow');
    }
    
    // ==================== Mock Classes ====================
    
    private class PaymentSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"pi_test_success","status":"succeeded","amount":10000}');
            return res;
        }
    }
    
    private class PaymentFailedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(402);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"error":{"code":"card_declined","message":"Your card was declined."}}');
            return res;
        }
    }
}
