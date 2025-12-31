/**
 * @description Scheduler for transaction synchronization batch job.
 * Recommended schedule: Run every 4 hours to catch settlement updates.
 * 
 * Schedule examples:
 * // Every 4 hours starting at 2 AM
 * TransactionSyncScheduler.scheduleEveryFourHours();
 * 
 * // Custom schedule
 * System.schedule('Txn Sync 6AM', '0 0 6 * * ?', new TransactionSyncScheduler());
 */
public class TransactionSyncScheduler implements Schedulable {
    
    private Id gatewayId;
    
    public TransactionSyncScheduler() {
        this.gatewayId = null;
    }
    
    public TransactionSyncScheduler(Id gatewayId) {
        this.gatewayId = gatewayId;
    }
    
    public void execute(SchedulableContext sc) {
        TransactionSyncBatch batch;
        
        if (this.gatewayId != null) {
            batch = new TransactionSyncBatch(this.gatewayId);
        } else {
            batch = new TransactionSyncBatch();
        }
        
        // Use batch size of 50 to manage callout limits (100 callouts per transaction)
        Database.executeBatch(batch, 50);
    }
    
    /**
     * @description Schedule sync to run every 4 hours
     */
    public static void scheduleEveryFourHours() {
        // Abort existing jobs first
        unscheduleAll();
        
        // Schedule at 2 AM, 6 AM, 10 AM, 2 PM, 6 PM, 10 PM
        List<Integer> hours = new List<Integer>{ 2, 6, 10, 14, 18, 22 };
        
        for (Integer hour : hours) {
            String jobName = 'Transaction Sync - ' + hour + ':00';
            String cronExp = '0 0 ' + hour + ' * * ?';
            System.schedule(jobName, cronExp, new TransactionSyncScheduler());
        }
    }
    
    /**
     * @description Schedule sync to run every hour (for high-volume orgs)
     */
    public static void scheduleHourly() {
        unscheduleAll();
        
        for (Integer hour = 0; hour < 24; hour++) {
            String jobName = 'Transaction Sync - ' + String.valueOf(hour).leftPad(2, '0') + ':00';
            String cronExp = '0 0 ' + hour + ' * * ?';
            System.schedule(jobName, cronExp, new TransactionSyncScheduler());
        }
    }
    
    /**
     * @description Schedule sync twice daily (morning and evening)
     */
    public static void scheduleTwiceDaily() {
        unscheduleAll();
        
        System.schedule('Transaction Sync - Morning', '0 0 6 * * ?', new TransactionSyncScheduler());
        System.schedule('Transaction Sync - Evening', '0 0 18 * * ?', new TransactionSyncScheduler());
    }
    
    /**
     * @description Unschedule all transaction sync jobs
     */
    public static void unscheduleAll() {
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'Transaction Sync%'
        ];
        
        for (CronTrigger ct : jobs) {
            System.abortJob(ct.Id);
        }
    }
    
    /**
     * @description Run sync immediately (for testing or manual execution)
     */
    public static Id runNow() {
        return Database.executeBatch(new TransactionSyncBatch(), 50);
    }
    
    /**
     * @description Run sync for a specific gateway
     */
    public static Id runForGateway(Id gatewayId) {
        return Database.executeBatch(new TransactionSyncBatch(gatewayId), 50);
    }
}
