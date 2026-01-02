/**
 * @description Queueable class to asynchronously create Order and Invoice from a Call Center transaction
 * Handles the payment-first workflow where payment is captured before order/invoice creation
 */
public class OrderFulfillmentQueueable implements Queueable {
    
    private Id transactionId;
    
    /**
     * @description Constructor
     * @param transactionId The Transaction record Id to process
     */
    public OrderFulfillmentQueueable(Id transactionId) {
        this.transactionId = transactionId;
    }
    
    /**
     * @description Execute the queueable job
     * @param context The queueable context
     */
    public void execute(QueueableContext context) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Query the transaction and line items
            pymts__Transaction__c txn = [
                SELECT Id, Name, pymts__Account__c, pymts__Amount__c, pymts__Sales_Channel__c,
                       pymts__Fulfillment_Status__c, pymts__Source_Description__c,
                       pymts__Account__r.Name
                FROM pymts__Transaction__c
                WHERE Id = :transactionId
            ];
            
            List<pymts__Transaction_Line_Item__c> lineItems = [
                SELECT Id, pymts__Product__c, pymts__Product__r.Name, pymts__Quantity__c,
                       pymts__Unit_Price__c, pymts__Total_Price__c, pymts__Description__c
                FROM pymts__Transaction_Line_Item__c
                WHERE pymts__Transaction__c = :transactionId
            ];
            
            if (lineItems.isEmpty()) {
                throw new OrderFulfillmentException('No line items found for transaction');
            }
            
            // Get standard pricebook
            Id pricebookId = getStandardPricebookId();
            
            // Create Order
            Order newOrder = new Order(
                AccountId = txn.pymts__Account__c,
                Status = 'Draft',
                EffectiveDate = Date.today(),
                Pricebook2Id = pricebookId,
                Description = 'Created from Call Center Transaction: ' + txn.Name
            );
            insert newOrder;
            
            // Get PricebookEntries for the products
            Set<Id> productIds = new Set<Id>();
            for (pymts__Transaction_Line_Item__c li : lineItems) {
                productIds.add(li.pymts__Product__c);
            }
            
            Map<Id, PricebookEntry> productToPbe = new Map<Id, PricebookEntry>();
            for (PricebookEntry pbe : [
                SELECT Id, Product2Id, UnitPrice
                FROM PricebookEntry
                WHERE Pricebook2Id = :pricebookId
                  AND Product2Id IN :productIds
            ]) {
                productToPbe.put(pbe.Product2Id, pbe);
            }
            
            // Create Order Items
            List<OrderItem> orderItems = new List<OrderItem>();
            Map<Id, pymts__Transaction_Line_Item__c> lineItemMap = new Map<Id, pymts__Transaction_Line_Item__c>();
            
            for (pymts__Transaction_Line_Item__c li : lineItems) {
                PricebookEntry pbe = productToPbe.get(li.pymts__Product__c);
                if (pbe == null) {
                    throw new OrderFulfillmentException('No pricebook entry found for product: ' + li.pymts__Product__r.Name);
                }
                
                OrderItem oi = new OrderItem(
                    OrderId = newOrder.Id,
                    PricebookEntryId = pbe.Id,
                    Quantity = li.pymts__Quantity__c,
                    UnitPrice = li.pymts__Unit_Price__c,
                    Description = li.pymts__Description__c
                );
                orderItems.add(oi);
                lineItemMap.put(li.Id, li);
            }
            insert orderItems;
            
            // Activate the Order
            newOrder.Status = 'Activated';
            update newOrder;
            
            // Update Transaction Line Items with Order Product references
            List<pymts__Transaction_Line_Item__c> lineItemsToUpdate = new List<pymts__Transaction_Line_Item__c>();
            Integer idx = 0;
            for (pymts__Transaction_Line_Item__c li : lineItems) {
                li.pymts__Order_Product__c = orderItems[idx].Id;
                lineItemsToUpdate.add(li);
                idx++;
            }
            update lineItemsToUpdate;
            
            // Create Invoice
            pymts__Invoice__c invoice = new pymts__Invoice__c(
                pymts__Account__c = txn.pymts__Account__c,
                pymts__Order__c = newOrder.Id,
                pymts__Status__c = 'Paid',
                pymts__Invoice_Date__c = Date.today(),
                pymts__Due_Date__c = Date.today(),
                pymts__Total_Amount__c = txn.pymts__Amount__c,
                pymts__Amount_Paid__c = txn.pymts__Amount__c
            );
            insert invoice;
            
            // Create Invoice Line Items
            List<pymts__Invoice_Line_Item__c> invoiceLineItems = new List<pymts__Invoice_Line_Item__c>();
            for (pymts__Transaction_Line_Item__c li : lineItems) {
                pymts__Invoice_Line_Item__c ili = new pymts__Invoice_Line_Item__c(
                    pymts__Invoice__c = invoice.Id,
                    pymts__Product__c = li.pymts__Product__c,
                    pymts__Quantity__c = li.pymts__Quantity__c,
                    pymts__Unit_Price__c = li.pymts__Unit_Price__c,
                    pymts__Description__c = li.pymts__Description__c
                );
                invoiceLineItems.add(ili);
            }
            insert invoiceLineItems;
            
            // Create Payment Allocation
            pymts__Payment_Allocation__c allocation = new pymts__Payment_Allocation__c(
                pymts__Transaction__c = txn.Id,
                pymts__Invoice__c = invoice.Id,
                pymts__Amount__c = txn.pymts__Amount__c,
                pymts__Allocation_Date__c = Date.today()
            );
            insert allocation;
            
            // Update Transaction with Order reference and Complete status
            txn.pymts__Order__c = newOrder.Id;
            txn.pymts__Fulfillment_Status__c = 'Complete';
            update txn;
            
            // Create Audit Log
            createAuditLog(txn.Id, 'Fulfillment Complete', 
                'Order ' + newOrder.Id + ' and Invoice ' + invoice.Id + ' created successfully');
            
        } catch (Exception e) {
            // Rollback all changes
            Database.rollback(sp);
            
            // Update Transaction with error
            try {
                pymts__Transaction__c txn = new pymts__Transaction__c(
                    Id = transactionId,
                    pymts__Fulfillment_Status__c = 'Failed',
                    pymts__Fulfillment_Error__c = e.getMessage() + '\n' + e.getStackTraceString()
                );
                update txn;
                
                // Create audit log for failure
                createAuditLog(transactionId, 'Fulfillment Failed', e.getMessage());
                
                // Send notification to supervisor
                sendFailureNotification(transactionId, e.getMessage());
                
                // Create follow-up task
                createFollowUpTask(transactionId, e.getMessage());
                
            } catch (Exception updateEx) {
                System.debug('Error updating transaction with failure: ' + updateEx.getMessage());
            }
        }
    }
    
    /**
     * @description Get the standard pricebook Id
     */
    private Id getStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }
    
    /**
     * @description Create an audit log entry
     */
    private void createAuditLog(Id transactionId, String action, String details) {
        try {
            pymts__Audit_Log__c log = new pymts__Audit_Log__c(
                pymts__Transaction__c = transactionId,
                pymts__Action__c = action,
                pymts__Details__c = details,
                pymts__Timestamp__c = DateTime.now(),
                pymts__User__c = UserInfo.getUserId()
            );
            insert log;
        } catch (Exception e) {
            System.debug('Error creating audit log: ' + e.getMessage());
        }
    }
    
    /**
     * @description Send a bell notification to supervisors about fulfillment failure
     */
    private void sendFailureNotification(Id transactionId, String errorMessage) {
        try {
            // Get users with Payment_Admin permission set
            List<PermissionSetAssignment> admins = [
                SELECT AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSet.Name = 'Payment_Admin'
                LIMIT 10
            ];
            
            if (admins.isEmpty()) {
                return;
            }
            
            Set<String> recipientIds = new Set<String>();
            for (PermissionSetAssignment psa : admins) {
                recipientIds.add(psa.AssigneeId);
            }
            
            // Query transaction details
            pymts__Transaction__c txn = [
                SELECT Name, pymts__Amount__c, pymts__Account__r.Name
                FROM pymts__Transaction__c
                WHERE Id = :transactionId
            ];
            
            // Send custom notification
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Order Fulfillment Failed');
            notification.setBody('Transaction ' + txn.Name + ' for ' + txn.pymts__Account__r.Name + 
                ' ($' + txn.pymts__Amount__c + ') failed to create Order/Invoice. Manual intervention required.');
            notification.setTargetId(transactionId);
            
            // Get notification type
            CustomNotificationType notificationType = [
                SELECT Id FROM CustomNotificationType 
                WHERE DeveloperName = 'Payment_Notification' 
                LIMIT 1
            ];
            notification.setNotificationTypeId(notificationType.Id);
            
            notification.send(recipientIds);
            
        } catch (Exception e) {
            System.debug('Error sending failure notification: ' + e.getMessage());
        }
    }
    
    /**
     * @description Create a follow-up task for failed fulfillment
     */
    private void createFollowUpTask(Id transactionId, String errorMessage) {
        try {
            // Get first admin user
            List<PermissionSetAssignment> admins = [
                SELECT AssigneeId
                FROM PermissionSetAssignment
                WHERE PermissionSet.Name = 'Payment_Admin'
                LIMIT 1
            ];
            
            Id ownerId = admins.isEmpty() ? UserInfo.getUserId() : admins[0].AssigneeId;
            
            pymts__Transaction__c txn = [
                SELECT Name, pymts__Account__c, pymts__Account__r.Name, pymts__Amount__c
                FROM pymts__Transaction__c
                WHERE Id = :transactionId
            ];
            
            Task followUp = new Task(
                Subject = 'Resolve Failed Order Fulfillment - ' + txn.Name,
                Description = 'Transaction ' + txn.Name + ' payment succeeded but Order/Invoice creation failed.\n\n' +
                    'Amount: $' + txn.pymts__Amount__c + '\n' +
                    'Account: ' + txn.pymts__Account__r.Name + '\n\n' +
                    'Error: ' + errorMessage + '\n\n' +
                    'Action Required: Manually create the Order and Invoice, or process a refund if necessary.',
                WhatId = transactionId,
                OwnerId = ownerId,
                Priority = 'High',
                Status = 'Not Started',
                ActivityDate = Date.today()
            );
            insert followUp;
            
        } catch (Exception e) {
            System.debug('Error creating follow-up task: ' + e.getMessage());
        }
    }
    
    /**
     * @description Custom exception for fulfillment errors
     */
    public class OrderFulfillmentException extends Exception {}
}
