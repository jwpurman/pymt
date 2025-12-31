/**
 * @description Batch job to synchronize transaction settlement status with payment gateways.
 * Essential for ACH transactions that take 3-5 business days to settle and can be returned.
 * 
 * Schedule: Run multiple times daily (e.g., every 4 hours)
 * System.schedule('Transaction Sync - Morning', '0 0 6 * * ?', new TransactionSyncScheduler());
 * System.schedule('Transaction Sync - Midday', '0 0 12 * * ?', new TransactionSyncScheduler());
 * System.schedule('Transaction Sync - Evening', '0 0 18 * * ?', new TransactionSyncScheduler());
 */
public class TransactionSyncBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
    
    private Integer syncedCount = 0;
    private Integer settledCount = 0;
    private Integer returnedCount = 0;
    private Integer errorCount = 0;
    private List<String> errors = new List<String>();
    private Id specificGatewayId;
    
    // ACH Return Reason Codes and descriptions
    private static final Map<String, String> ACH_RETURN_CODES = new Map<String, String>{
        'R01' => 'Insufficient Funds',
        'R02' => 'Account Closed',
        'R03' => 'No Account/Unable to Locate Account',
        'R04' => 'Invalid Account Number',
        'R05' => 'Improper Debit to Consumer Account',
        'R06' => 'Returned per ODFI Request',
        'R07' => 'Authorization Revoked by Customer',
        'R08' => 'Payment Stopped',
        'R09' => 'Uncollected Funds',
        'R10' => 'Customer Advises Originator is Not Known',
        'R11' => 'Customer Advises Entry Not in Accordance with Terms',
        'R12' => 'Account Sold to Another DFI',
        'R13' => 'Invalid ACH Routing Number',
        'R14' => 'Representative Payee Deceased',
        'R15' => 'Beneficiary or Account Holder Deceased',
        'R16' => 'Account Frozen',
        'R17' => 'File Record Edit Criteria',
        'R20' => 'Non-Transaction Account',
        'R21' => 'Invalid Company Identification',
        'R22' => 'Invalid Individual ID Number',
        'R23' => 'Credit Entry Refused by Receiver',
        'R24' => 'Duplicate Entry',
        'R29' => 'Corporate Customer Advises Not Authorized',
        'R31' => 'Permissible Return Entry',
        'R33' => 'Return of XCK Entry'
    };
    
    public TransactionSyncBatch() {
        this.specificGatewayId = null;
    }
    
    public TransactionSyncBatch(Id gatewayId) {
        this.specificGatewayId = gatewayId;
    }
    
    /**
     * @description Query for transactions that need settlement status sync
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Query transactions that are:
        // 1. Approved but not yet settled
        // 2. Pending Settlement
        // 3. ACH transactions within the return window (60 days)
        
        Date achReturnWindow = Date.today().addDays(-60);
        
        String query = 'SELECT Id, Name, pymtTest__Gateway_Transaction_Id__c, pymtTest__Payment_Gateway__c, ' +
            'pymtTest__Payment_Gateway__r.pymtTest__Gateway_Type__c, pymtTest__Status__c, ' +
            'pymtTest__Settlement_Status__c, pymtTest__Payment_Type__c, pymtTest__Amount__c, ' +
            'pymtTest__Account__c, pymtTest__Last_Sync_Date__c, pymtTest__Expected_Settlement_Date__c, ' +
            'CreatedDate ' +
            'FROM pymtTest__Transaction__c ' +
            'WHERE pymtTest__Status__c IN (\'Approved\', \'Pending\') ' +
            'AND pymtTest__Settlement_Status__c IN (\'Pending\', \'Pending Settlement\') ' +
            'AND pymtTest__Gateway_Transaction_Id__c != null ';
        
        if (this.specificGatewayId != null) {
            query += 'AND pymtTest__Payment_Gateway__c = :specificGatewayId ';
        }
        
        // Include ACH transactions that might still be returned
        query += 'OR (pymtTest__Payment_Type__c = \'ACH\' ' +
            'AND pymtTest__Settlement_Status__c = \'Settled\' ' +
            'AND CreatedDate >= :achReturnWindow) ';
        
        query += 'ORDER BY pymtTest__Payment_Gateway__c, CreatedDate ASC';
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * @description Process each batch of transactions
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<pymtTest__Transaction__c> transactions = (List<pymtTest__Transaction__c>) scope;
        // Group transactions by gateway for efficient API calls
        Map<Id, List<pymtTest__Transaction__c>> txnsByGateway = new Map<Id, List<pymtTest__Transaction__c>>();
        
        for (pymtTest__Transaction__c txn : transactions) {
            if (!txnsByGateway.containsKey(txn.pymtTest__Payment_Gateway__c)) {
                txnsByGateway.put(txn.pymtTest__Payment_Gateway__c, new List<pymtTest__Transaction__c>());
            }
            txnsByGateway.get(txn.pymtTest__Payment_Gateway__c).add(txn);
        }
        
        // Process each gateway's transactions
        for (Id gatewayId : txnsByGateway.keySet()) {
            List<pymtTest__Transaction__c> gatewayTxns = txnsByGateway.get(gatewayId);
            String gatewayType = gatewayTxns[0].pymtTest__Payment_Gateway__r.pymtTest__Gateway_Type__c;
            
            try {
                syncGatewayTransactions(gatewayId, gatewayType, gatewayTxns);
            } catch (Exception e) {
                errorCount++;
                errors.add('Gateway ' + gatewayId + ': ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Sync transactions for a specific gateway
     */
    private void syncGatewayTransactions(Id gatewayId, String gatewayType, List<pymtTest__Transaction__c> transactions) {
        List<pymtTest__Transaction__c> toUpdate = new List<pymtTest__Transaction__c>();
        List<pymtTest__Audit_Log__c> auditLogs = new List<pymtTest__Audit_Log__c>();
        
        switch on gatewayType {
            when 'Authorize.Net' {
                syncAuthorizeNetTransactions(gatewayId, transactions, toUpdate, auditLogs);
            }
            when 'Stripe' {
                syncStripeTransactions(gatewayId, transactions, toUpdate, auditLogs);
            }
            when else {
                // Gateway type not yet supported for sync
                return;
            }
        }
        
        // Update transactions
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        
        // Create audit logs
        if (!auditLogs.isEmpty()) {
            insert auditLogs;
        }
    }
    
    /**
     * @description Sync transactions with Authorize.Net
     */
    private void syncAuthorizeNetTransactions(Id gatewayId, List<pymtTest__Transaction__c> transactions,
                                              List<pymtTest__Transaction__c> toUpdate, 
                                              List<pymtTest__Audit_Log__c> auditLogs) {
        AuthorizeNetGateway gateway = new AuthorizeNetGateway(gatewayId);
        
        for (pymtTest__Transaction__c txn : transactions) {
            try {
                AuthorizeNetGateway.TransactionDetails details = 
                    gateway.getTransactionDetails(txn.pymtTest__Gateway_Transaction_Id__c);
                
                if (details.success) {
                    syncedCount++;
                    
                    // Check for status changes
                    String newSettlementStatus = mapAuthNetSettlementStatus(details);
                    Boolean statusChanged = newSettlementStatus != txn.pymtTest__Settlement_Status__c;
                    
                    // Update transaction
                    txn.pymtTest__Last_Sync_Date__c = DateTime.now();
                    txn.pymtTest__Settlement_Status__c = newSettlementStatus;
                    
                    if (details.settlementDate != null) {
                        txn.pymtTest__Settlement_Date__c = details.settlementDate;
                    }
                    
                    // Handle ACH returns
                    if (details.isReturned) {
                        handleACHReturn(txn, details, auditLogs);
                        returnedCount++;
                    } else if (newSettlementStatus == 'Settled') {
                        settledCount++;
                        
                        if (statusChanged) {
                            createAuditLog(auditLogs, txn, 'Transaction Settled', 
                                'Transaction settled on ' + details.settlementDate);
                        }
                    }
                    
                    toUpdate.add(txn);
                }
                
            } catch (Exception e) {
                errorCount++;
                errors.add(txn.Name + ': ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Sync transactions with Stripe
     */
    private void syncStripeTransactions(Id gatewayId, List<pymtTest__Transaction__c> transactions,
                                        List<pymtTest__Transaction__c> toUpdate,
                                        List<pymtTest__Audit_Log__c> auditLogs) {
        StripeGateway gateway = new StripeGateway(gatewayId);
        
        for (pymtTest__Transaction__c txn : transactions) {
            try {
                // Stripe PaymentIntents settle quickly for cards
                // For ACH (via Stripe), check the charge status
                Map<String, Object> chargeDetails = gateway.getChargeDetails(txn.pymtTest__Gateway_Transaction_Id__c);
                
                if (chargeDetails != null) {
                    syncedCount++;
                    
                    String status = (String) chargeDetails.get('status');
                    Boolean captured = (Boolean) chargeDetails.get('captured');
                    
                    txn.pymtTest__Last_Sync_Date__c = DateTime.now();
                    
                    if (status == 'succeeded' && captured == true) {
                        if (txn.pymtTest__Settlement_Status__c != 'Settled') {
                            txn.pymtTest__Settlement_Status__c = 'Settled';
                            txn.pymtTest__Settlement_Date__c = DateTime.now();
                            settledCount++;
                            
                            createAuditLog(auditLogs, txn, 'Transaction Settled', 
                                'Stripe transaction settled successfully');
                        }
                    } else if (status == 'failed') {
                        txn.pymtTest__Settlement_Status__c = 'Settlement Error';
                        txn.pymtTest__Status__c = 'Declined';
                        
                        String failureMessage = (String) chargeDetails.get('failure_message');
                        createAuditLog(auditLogs, txn, 'Settlement Failed', failureMessage);
                        
                        // Reverse invoice payment
                        reverseInvoicePayment(txn.Id);
                    }
                    
                    toUpdate.add(txn);
                }
                
            } catch (Exception e) {
                errorCount++;
                errors.add(txn.Name + ': ' + e.getMessage());
            }
        }
    }
    
    /**
     * @description Map Authorize.Net settlement status to our status
     */
    private String mapAuthNetSettlementStatus(AuthorizeNetGateway.TransactionDetails details) {
        if (details.isReturned) {
            return 'Returned';
        }
        
        String state = details.settlementState;
        
        if (state == 'settledSuccessfully') {
            return 'Settled';
        } else if (state == 'pendingSettlement') {
            return 'Pending Settlement';
        } else if (state == 'settlementError' || state == 'communicationError') {
            return 'Settlement Error';
        } else if (state == 'voided') {
            return 'Voided';
        }
        
        return 'Pending';
    }
    
    /**
     * @description Handle ACH return - reverse payment and update records
     */
    private void handleACHReturn(pymtTest__Transaction__c txn, 
                                 AuthorizeNetGateway.TransactionDetails details,
                                 List<pymtTest__Audit_Log__c> auditLogs) {
        // Update transaction status
        txn.pymtTest__Status__c = 'Returned';
        txn.pymtTest__Settlement_Status__c = 'Returned';
        txn.pymtTest__Return_Reason_Code__c = details.returnReasonCode;
        
        // Get return description
        String returnDescription = ACH_RETURN_CODES.containsKey(details.returnReasonCode) ?
            ACH_RETURN_CODES.get(details.returnReasonCode) : details.returnDescription;
        
        // Create audit log
        createAuditLog(auditLogs, txn, 'ACH Return', 
            'ACH transaction returned. Code: ' + details.returnReasonCode + 
            ' - ' + returnDescription);
        
        // Reverse the invoice payment
        reverseInvoicePayment(txn.Id);
        
        // Send notification
        sendReturnNotification(txn, details.returnReasonCode, returnDescription);
    }
    
    /**
     * @description Reverse invoice payment when transaction fails/returns
     */
    private void reverseInvoicePayment(Id transactionId) {
        // Get allocations for this transaction
        List<pymtTest__Payment_Allocation__c> allocations = [
            SELECT Id, pymtTest__Invoice__c, pymtTest__Amount__c
            FROM pymtTest__Payment_Allocation__c
            WHERE pymtTest__Transaction__c = :transactionId
        ];
        
        if (allocations.isEmpty()) return;
        
        // Get affected invoices
        Set<Id> invoiceIds = new Set<Id>();
        Map<Id, Decimal> reverseAmounts = new Map<Id, Decimal>();
        
        for (pymtTest__Payment_Allocation__c alloc : allocations) {
            invoiceIds.add(alloc.pymtTest__Invoice__c);
            reverseAmounts.put(alloc.pymtTest__Invoice__c, alloc.pymtTest__Amount__c);
        }
        
        // Update invoices
        List<pymtTest__Invoice__c> invoices = [
            SELECT Id, pymtTest__Amount_Paid__c, pymtTest__Total_Amount__c, pymtTest__Status__c
            FROM pymtTest__Invoice__c
            WHERE Id IN :invoiceIds
        ];
        
        for (pymtTest__Invoice__c inv : invoices) {
            Decimal reverseAmount = reverseAmounts.get(inv.Id);
            inv.pymtTest__Amount_Paid__c = Math.max(0, inv.pymtTest__Amount_Paid__c - reverseAmount);
            
            // Update status
            if (inv.pymtTest__Amount_Paid__c <= 0) {
                inv.pymtTest__Status__c = 'Pending';
            } else if (inv.pymtTest__Amount_Paid__c < inv.pymtTest__Total_Amount__c) {
                inv.pymtTest__Status__c = 'Partially Paid';
            }
        }
        
        update invoices;
        
        // Also reverse any account credits that were created
        List<pymtTest__Account_Credit__c> credits = [
            SELECT Id FROM pymtTest__Account_Credit__c
            WHERE pymtTest__Source_Transaction__c = :transactionId
        ];
        
        if (!credits.isEmpty()) {
            delete credits;
        }
    }
    
    /**
     * @description Send notification for ACH return
     */
    private void sendReturnNotification(pymtTest__Transaction__c txn, String returnCode, String returnDescription) {
        // Create bell notification
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('ACH Payment Returned');
            notification.setBody('Payment ' + txn.Name + ' was returned. Reason: ' + 
                                returnCode + ' - ' + returnDescription);
            notification.setNotificationTypeId(getNotificationTypeId());
            notification.setTargetId(txn.Id);
            
            // Send to account owner and payment admins
            Set<String> recipients = getNotificationRecipients(txn.pymtTest__Account__c);
            if (!recipients.isEmpty()) {
                notification.send(recipients);
            }
        } catch (Exception e) {
            System.debug('Failed to send return notification: ' + e.getMessage());
        }
    }
    
    private Id getNotificationTypeId() {
        List<CustomNotificationType> types = [
            SELECT Id FROM CustomNotificationType 
            WHERE DeveloperName = 'Payment_Notification' LIMIT 1
        ];
        return types.isEmpty() ? null : types[0].Id;
    }
    
    private Set<String> getNotificationRecipients(Id accountId) {
        Set<String> recipients = new Set<String>();
        
        // Add account owner
        if (accountId != null) {
            List<Account> accounts = [SELECT OwnerId FROM Account WHERE Id = :accountId LIMIT 1];
            if (!accounts.isEmpty()) {
                recipients.add(accounts[0].OwnerId);
            }
        }
        
        // Add payment admins
        List<PermissionSetAssignment> admins = [
            SELECT AssigneeId FROM PermissionSetAssignment
            WHERE PermissionSet.Name = 'Payment_Admin'
            LIMIT 10
        ];
        for (PermissionSetAssignment psa : admins) {
            recipients.add(psa.AssigneeId);
        }
        
        return recipients;
    }
    
    private void createAuditLog(List<pymtTest__Audit_Log__c> logs, pymtTest__Transaction__c txn, 
                               String action, String details) {
        logs.add(new pymtTest__Audit_Log__c(
            pymtTest__Action__c = action,
            pymtTest__Transaction__c = txn.Id,
            pymtTest__Account__c = txn.pymtTest__Account__c,
            pymtTest__Details__c = details,
            pymtTest__Timestamp__c = DateTime.now()
        ));
    }
    
    /**
     * @description Finish - send summary notification
     */
    public void finish(Database.BatchableContext bc) {
        String summary = 'Transaction Sync Complete\n' +
            'Synced: ' + syncedCount + '\n' +
            'Settled: ' + settledCount + '\n' +
            'Returned: ' + returnedCount + '\n' +
            'Errors: ' + errorCount;
        
        if (!errors.isEmpty()) {
            summary += '\n\nErrors:\n' + String.join(errors, '\n');
        }
        
        System.debug(summary);
        
        // If there were returns, ensure admins are notified
        if (returnedCount > 0) {
            // Optionally send email summary
        }
    }
    
    /**
     * @description Get human-readable ACH return description
     */
    public static String getACHReturnDescription(String returnCode) {
        return ACH_RETURN_CODES.containsKey(returnCode) ? 
            ACH_RETURN_CODES.get(returnCode) : 'Unknown return reason';
    }
}
