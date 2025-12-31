/**
 * @description Service class for invoice operations.
 * Handles invoice generation from Orders, invoice management, and status updates.
 */
public with sharing class InvoiceService {
    
    /**
     * @description Generate invoices from an Order based on payment frequency
     * @param orderId The Order ID
     * @return List<Id> The IDs of created invoices
     */
    @AuraEnabled
    public static List<Id> generateInvoicesFromOrder(Id orderId) {
        try {
            Order ord = [
                SELECT Id, OrderNumber, AccountId, EffectiveDate, EndDate,
                       pymtTest__Payment_Frequency__c, TotalAmount,
                       (SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice, 
                        TotalPrice, Product2.pymtTest__Is_Recurring__c
                        FROM OrderItems)
                FROM Order
                WHERE Id = :orderId
            ];
            
            // Validate order
            if (ord.EffectiveDate == null) {
                throw new InvoiceServiceException('Order EffectiveDate is required');
            }
            
            String frequency = ord.pymtTest__Payment_Frequency__c != null ? 
                              ord.pymtTest__Payment_Frequency__c : 'One-Time';
            
            // Calculate invoice dates and amounts
            List<InvoiceData> invoiceDataList = calculateInvoiceSchedule(ord, frequency);
            
            // Create invoices
            List<pymtTest__Invoice__c> invoices = new List<pymtTest__Invoice__c>();
            for (InvoiceData data : invoiceDataList) {
                pymtTest__Invoice__c inv = new pymtTest__Invoice__c(
                    pymtTest__Account__c = ord.AccountId,
                    pymtTest__Order__c = ord.Id,
                    pymtTest__Total_Amount__c = data.amount,
                    pymtTest__Due_Date__c = data.dueDate,
                    pymtTest__Scheduled_Payment_Date__c = data.dueDate,
                    pymtTest__Status__c = 'Scheduled',
                    pymtTest__Auto_Pay__c = true,
                    pymtTest__Amount_Paid__c = 0
                );
                invoices.add(inv);
            }
            
            insert invoices;
            
            // Create invoice line items
            List<pymtTest__Invoice_Line_Item__c> lineItems = new List<pymtTest__Invoice_Line_Item__c>();
            
            for (Integer i = 0; i < invoices.size(); i++) {
                pymtTest__Invoice__c inv = invoices[i];
                InvoiceData data = invoiceDataList[i];
                
                for (LineItemData lid : data.lineItems) {
                    lineItems.add(new pymtTest__Invoice_Line_Item__c(
                        pymtTest__Invoice__c = inv.Id,
                        pymtTest__Description__c = lid.description,
                        pymtTest__Quantity__c = lid.quantity,
                        pymtTest__Unit_Price__c = lid.unitPrice
                    ));
                }
            }
            
            insert lineItems;
            
            // Return invoice IDs
            List<Id> invoiceIds = new List<Id>();
            for (pymtTest__Invoice__c inv : invoices) {
                invoiceIds.add(inv.Id);
            }
            
            return invoiceIds;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error generating invoices: ' + e.getMessage());
        }
    }
    
    /**
     * @description Calculate invoice schedule based on frequency
     */
    private static List<InvoiceData> calculateInvoiceSchedule(Order ord, String frequency) {
        List<InvoiceData> schedule = new List<InvoiceData>();
        
        Date startDate = ord.EffectiveDate;
        Date endDate = ord.EndDate != null ? ord.EndDate : startDate;
        
        // Separate one-time and recurring items
        Decimal oneTimeTotal = 0;
        Decimal recurringTotal = 0;
        List<OrderItem> oneTimeItems = new List<OrderItem>();
        List<OrderItem> recurringItems = new List<OrderItem>();
        
        for (OrderItem oi : ord.OrderItems) {
            Boolean isRecurring = oi.Product2.pymtTest__Is_Recurring__c == true;
            if (isRecurring) {
                recurringTotal += oi.TotalPrice;
                recurringItems.add(oi);
            } else {
                oneTimeTotal += oi.TotalPrice;
                oneTimeItems.add(oi);
            }
        }
        
        // If all items are one-time or frequency is One-Time, create single invoice
        if (frequency == 'One-Time' || recurringItems.isEmpty()) {
            InvoiceData data = new InvoiceData();
            data.dueDate = startDate;
            data.amount = ord.TotalAmount;
            data.lineItems = new List<LineItemData>();
            
            for (OrderItem oi : ord.OrderItems) {
                data.lineItems.add(new LineItemData(
                    oi.Product2.Name,
                    oi.Quantity,
                    oi.UnitPrice
                ));
            }
            
            schedule.add(data);
            return schedule;
        }
        
        // Calculate number of periods
        Integer numberOfPeriods = calculateNumberOfPeriods(startDate, endDate, frequency);
        Decimal amountPerPeriod = recurringTotal / numberOfPeriods;
        
        // Create first invoice with one-time items + first recurring payment
        InvoiceData firstInvoice = new InvoiceData();
        firstInvoice.dueDate = startDate;
        firstInvoice.amount = oneTimeTotal + amountPerPeriod;
        firstInvoice.lineItems = new List<LineItemData>();
        
        // Add one-time items to first invoice
        for (OrderItem oi : oneTimeItems) {
            firstInvoice.lineItems.add(new LineItemData(
                oi.Product2.Name,
                oi.Quantity,
                oi.UnitPrice
            ));
        }
        
        // Add prorated recurring items to first invoice
        for (OrderItem oi : recurringItems) {
            Decimal proratedPrice = oi.UnitPrice / numberOfPeriods;
            firstInvoice.lineItems.add(new LineItemData(
                oi.Product2.Name + ' (Period 1 of ' + numberOfPeriods + ')',
                oi.Quantity,
                proratedPrice
            ));
        }
        
        schedule.add(firstInvoice);
        
        // Create subsequent invoices for recurring items
        Date nextDate = getNextDate(startDate, frequency);
        for (Integer i = 2; i <= numberOfPeriods; i++) {
            InvoiceData data = new InvoiceData();
            data.dueDate = nextDate;
            data.amount = amountPerPeriod;
            data.lineItems = new List<LineItemData>();
            
            for (OrderItem oi : recurringItems) {
                Decimal proratedPrice = oi.UnitPrice / numberOfPeriods;
                data.lineItems.add(new LineItemData(
                    oi.Product2.Name + ' (Period ' + i + ' of ' + numberOfPeriods + ')',
                    oi.Quantity,
                    proratedPrice
                ));
            }
            
            schedule.add(data);
            nextDate = getNextDate(nextDate, frequency);
        }
        
        return schedule;
    }
    
    /**
     * @description Calculate number of billing periods
     */
    private static Integer calculateNumberOfPeriods(Date startDate, Date endDate, String frequency) {
        Integer daysBetween = startDate.daysBetween(endDate);
        
        switch on frequency {
            when 'Weekly' {
                return Math.max(1, (daysBetween / 7) + 1);
            }
            when 'Monthly' {
                return Math.max(1, startDate.monthsBetween(endDate) + 1);
            }
            when 'Quarterly' {
                return Math.max(1, (startDate.monthsBetween(endDate) / 3) + 1);
            }
            when 'Annual' {
                return Math.max(1, (startDate.monthsBetween(endDate) / 12) + 1);
            }
            when else {
                return 1;
            }
        }
    }
    
    /**
     * @description Get next date based on frequency
     */
    private static Date getNextDate(Date currentDate, String frequency) {
        switch on frequency {
            when 'Weekly' {
                return currentDate.addDays(7);
            }
            when 'Monthly' {
                return currentDate.addMonths(1);
            }
            when 'Quarterly' {
                return currentDate.addMonths(3);
            }
            when 'Annual' {
                return currentDate.addYears(1);
            }
            when else {
                return currentDate;
            }
        }
    }
    
    /**
     * @description Get order details for invoice generation
     * @param orderId The Order ID
     * @return Order The order with related data
     */
    @AuraEnabled(cacheable=true)
    public static Order getOrderDetails(Id orderId) {
        return [
            SELECT Id, OrderNumber, AccountId, Account.Name, EffectiveDate, EndDate,
                   Status, TotalAmount, pymtTest__Payment_Frequency__c,
                   (SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice, 
                    TotalPrice, Description, Product2.pymtTest__Is_Recurring__c
                    FROM OrderItems)
            FROM Order
            WHERE Id = :orderId
        ];
    }
    
    /**
     * @description Preview invoices that would be generated from an order
     * @param orderId The Order ID
     * @param paymentTermsDays Payment terms in days
     * @return List<InvoicePreview> Preview of invoices to be generated
     */
    @AuraEnabled
    public static List<InvoicePreview> previewInvoices(Id orderId, Integer paymentTermsDays) {
        Order ord = [
            SELECT Id, OrderNumber, AccountId, EffectiveDate, EndDate,
                   pymtTest__Payment_Frequency__c, TotalAmount,
                   (SELECT Id, Product2Id, Product2.Name, Quantity, UnitPrice, 
                    TotalPrice, Product2.pymtTest__Is_Recurring__c
                    FROM OrderItems)
            FROM Order
            WHERE Id = :orderId
        ];
        
        String frequency = ord.pymtTest__Payment_Frequency__c != null ? 
                          ord.pymtTest__Payment_Frequency__c : 'One-Time';
        
        List<InvoiceData> invoiceDataList = calculateInvoiceSchedule(ord, frequency);
        List<InvoicePreview> previews = new List<InvoicePreview>();
        
        Integer invoiceNum = 1;
        for (InvoiceData data : invoiceDataList) {
            InvoicePreview preview = new InvoicePreview();
            preview.invoiceNumber = invoiceNum++;
            preview.amount = data.amount;
            preview.dueDate = data.dueDate;
            preview.description = data.description;
            previews.add(preview);
        }
        
        return previews;
    }
    
    /**
     * @description Cancel an invoice
     * @param invoiceId The invoice ID
     */
    @AuraEnabled
    public static void cancelInvoice(Id invoiceId) {
        try {
            pymtTest__Invoice__c invoice = [
                SELECT Id, pymtTest__Status__c, pymtTest__Amount_Paid__c
                FROM pymtTest__Invoice__c
                WHERE Id = :invoiceId
            ];
            
            if (invoice.pymtTest__Amount_Paid__c > 0) {
                throw new InvoiceServiceException('Cannot cancel an invoice with payments applied');
            }
            
            invoice.pymtTest__Status__c = 'Cancelled';
            update invoice;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error cancelling invoice: ' + e.getMessage());
        }
    }
    
    /**
     * @description Get invoice details with line items
     * @param invoiceId The invoice ID
     * @return InvoiceDetailWrapper The invoice details
     */
    @AuraEnabled(cacheable=true)
    public static InvoiceDetailWrapper getInvoiceDetails(Id invoiceId) {
        pymtTest__Invoice__c invoice = [
            SELECT Id, Name, pymtTest__Total_Amount__c, pymtTest__Amount_Paid__c,
                   pymtTest__Balance_Due__c, pymtTest__Due_Date__c, pymtTest__Status__c,
                   pymtTest__Account__c, pymtTest__Account__r.Name,
                   pymtTest__Order__c, pymtTest__Order__r.OrderNumber,
                   pymtTest__Payment_Gateway__c, pymtTest__Payment_Gateway__r.Name,
                   pymtTest__Scheduled_Payment_Date__c, pymtTest__Auto_Pay__c,
                   pymtTest__Retry_Count__c, CreatedDate,
                   (SELECT Id, pymtTest__Description__c, pymtTest__Quantity__c, 
                    pymtTest__Unit_Price__c, pymtTest__Total_Amount__c
                    FROM pymtTest__Invoice_Line_Items__r),
                   (SELECT Id, Name, pymtTest__Amount__c, 
                    pymtTest__Transaction__r.Name, pymtTest__Transaction__r.pymtTest__Status__c,
                    pymtTest__Transaction__r.CreatedDate
                    FROM pymtTest__Payment_Allocations__r)
            FROM pymtTest__Invoice__c
            WHERE Id = :invoiceId
        ];
        
        return new InvoiceDetailWrapper(invoice);
    }
    
    /**
     * @description Update invoice allocations
     * @param transactionId The transaction ID
     * @param allocations The new allocations
     */
    @AuraEnabled
    public static void updateAllocations(Id transactionId, List<AllocationUpdate> allocations) {
        try {
            // Get existing allocations
            List<pymtTest__Payment_Allocation__c> existing = [
                SELECT Id, pymtTest__Invoice__c, pymtTest__Amount__c
                FROM pymtTest__Payment_Allocation__c
                WHERE pymtTest__Transaction__c = :transactionId
            ];
            
            // Build map of changes
            Map<Id, Decimal> oldAmounts = new Map<Id, Decimal>();
            Map<Id, Id> allocationIds = new Map<Id, Id>();
            
            for (pymtTest__Payment_Allocation__c alloc : existing) {
                oldAmounts.put(alloc.pymtTest__Invoice__c, alloc.pymtTest__Amount__c);
                allocationIds.put(alloc.pymtTest__Invoice__c, alloc.Id);
            }
            
            // Update allocations and calculate invoice changes
            List<pymtTest__Payment_Allocation__c> toUpdate = new List<pymtTest__Payment_Allocation__c>();
            List<pymtTest__Payment_Allocation__c> toInsert = new List<pymtTest__Payment_Allocation__c>();
            Map<Id, Decimal> invoiceDeltas = new Map<Id, Decimal>();
            
            for (AllocationUpdate au : allocations) {
                Decimal oldAmount = oldAmounts.containsKey(au.invoiceId) ? 
                                   oldAmounts.get(au.invoiceId) : 0;
                Decimal delta = au.amount - oldAmount;
                invoiceDeltas.put(au.invoiceId, delta);
                
                if (allocationIds.containsKey(au.invoiceId)) {
                    // Update existing
                    toUpdate.add(new pymtTest__Payment_Allocation__c(
                        Id = allocationIds.get(au.invoiceId),
                        pymtTest__Amount__c = au.amount
                    ));
                } else {
                    // Create new
                    toInsert.add(new pymtTest__Payment_Allocation__c(
                        pymtTest__Transaction__c = transactionId,
                        pymtTest__Invoice__c = au.invoiceId,
                        pymtTest__Amount__c = au.amount
                    ));
                }
            }
            
            if (!toUpdate.isEmpty()) update toUpdate;
            if (!toInsert.isEmpty()) insert toInsert;
            
            // Update invoice amounts
            List<pymtTest__Invoice__c> invoices = [
                SELECT Id, pymtTest__Amount_Paid__c, pymtTest__Total_Amount__c, pymtTest__Status__c
                FROM pymtTest__Invoice__c
                WHERE Id IN :invoiceDeltas.keySet()
            ];
            
            for (pymtTest__Invoice__c inv : invoices) {
                inv.pymtTest__Amount_Paid__c += invoiceDeltas.get(inv.Id);
                updateInvoiceStatus(inv);
            }
            
            update invoices;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error updating allocations: ' + e.getMessage());
        }
    }
    
    private static void updateInvoiceStatus(pymtTest__Invoice__c invoice) {
        Decimal balance = invoice.pymtTest__Total_Amount__c - invoice.pymtTest__Amount_Paid__c;
        
        if (balance <= 0) {
            invoice.pymtTest__Status__c = 'Paid';
        } else if (invoice.pymtTest__Amount_Paid__c > 0) {
            invoice.pymtTest__Status__c = 'Partially Paid';
        }
    }
    
    // ========== Wrapper Classes ==========
    
    private class InvoiceData {
        public Date dueDate;
        public Decimal amount;
        public String description;
        public List<LineItemData> lineItems;
    }
    
    private class LineItemData {
        public String description;
        public Decimal quantity;
        public Decimal unitPrice;
        
        public LineItemData(String itemDescription, Decimal qty, Decimal price) {
            this.description = itemDescription;
            this.quantity = qty;
            this.unitPrice = price;
        }
    }
    
    public class AllocationUpdate {
        @AuraEnabled public Id invoiceId { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
    }
    
    public class InvoiceDetailWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        @AuraEnabled public Decimal amountPaid { get; set; }
        @AuraEnabled public Decimal balanceDue { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String orderNumber { get; set; }
        @AuraEnabled public String gatewayName { get; set; }
        @AuraEnabled public Boolean autoPay { get; set; }
        @AuraEnabled public List<LineItemWrapper> lineItems { get; set; }
        @AuraEnabled public List<PaymentWrapper> payments { get; set; }
        
        public InvoiceDetailWrapper(pymtTest__Invoice__c inv) {
            this.id = inv.Id;
            this.name = inv.Name;
            this.totalAmount = inv.pymtTest__Total_Amount__c;
            this.amountPaid = inv.pymtTest__Amount_Paid__c;
            this.balanceDue = inv.pymtTest__Balance_Due__c;
            this.dueDate = inv.pymtTest__Due_Date__c;
            this.status = inv.pymtTest__Status__c;
            this.accountName = inv.pymtTest__Account__r?.Name;
            this.orderNumber = inv.pymtTest__Order__r?.OrderNumber;
            this.gatewayName = inv.pymtTest__Payment_Gateway__r?.Name;
            this.autoPay = inv.pymtTest__Auto_Pay__c;
            
            this.lineItems = new List<LineItemWrapper>();
            for (pymtTest__Invoice_Line_Item__c li : inv.pymtTest__Invoice_Line_Items__r) {
                this.lineItems.add(new LineItemWrapper(li));
            }
            
            this.payments = new List<PaymentWrapper>();
            for (pymtTest__Payment_Allocation__c pa : inv.pymtTest__Payment_Allocations__r) {
                this.payments.add(new PaymentWrapper(pa));
            }
        }
    }
    
    public class LineItemWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public Decimal totalAmount { get; set; }
        
        public LineItemWrapper(pymtTest__Invoice_Line_Item__c li) {
            this.id = li.Id;
            this.description = li.pymtTest__Description__c;
            this.quantity = li.pymtTest__Quantity__c;
            this.unitPrice = li.pymtTest__Unit_Price__c;
            this.totalAmount = li.pymtTest__Total_Amount__c;
        }
    }
    
    public class PaymentWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String transactionName { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Datetime paymentDate { get; set; }
        
        public PaymentWrapper(pymtTest__Payment_Allocation__c pa) {
            this.id = pa.Id;
            this.amount = pa.pymtTest__Amount__c;
            this.transactionName = pa.pymtTest__Transaction__r?.Name;
            this.status = pa.pymtTest__Transaction__r?.pymtTest__Status__c;
            this.paymentDate = pa.CreatedDate;
        }
    }
    
    public class InvoicePreview {
        @AuraEnabled public Integer invoiceNumber { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Date dueDate { get; set; }
        @AuraEnabled public String description { get; set; }
    }
    
    public class InvoiceServiceException extends Exception {}
}
