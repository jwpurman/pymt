/**
 * @description Schedulable class to run recurring payment batch daily.
 * Schedule using: System.schedule('Daily Payment Processing', '0 0 6 * * ?', new RecurringPaymentScheduler());
 */
public class RecurringPaymentScheduler implements Schedulable {
    
    public void execute(SchedulableContext sc) {
        RecurringPaymentBatch batch = new RecurringPaymentBatch();
        Database.executeBatch(batch, 10); // Process 10 invoices at a time to manage callout limits
    }
    
    /**
     * @description Schedule the job to run daily at specified hour
     * @param hour The hour to run (0-23)
     * @return Id The scheduled job ID
     */
    public static Id scheduleDaily(Integer hour) {
        String jobName = 'Daily Payment Processing';
        String cronExp = '0 0 ' + hour + ' * * ?';
        
        // Check if already scheduled
        List<CronTrigger> existingJobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :jobName
        ];
        
        if (!existingJobs.isEmpty()) {
            // Abort existing job
            for (CronTrigger ct : existingJobs) {
                System.abortJob(ct.Id);
            }
        }
        
        return System.schedule(jobName, cronExp, new RecurringPaymentScheduler());
    }
    
    /**
     * @description Unschedule the job
     */
    public static void unschedule() {
        String jobName = 'Daily Payment Processing';
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :jobName
        ];
        
        for (CronTrigger ct : jobs) {
            System.abortJob(ct.Id);
        }
    }
}
