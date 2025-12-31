/**
 * @description Service class for Call Center payment-first workflow operations
 * Handles account search, product search, quick account creation, and payment processing
 */
public with sharing class CallCenterService {
    
    /**
     * @description Wrapper class for cart line items
     */
    public class CartItem {
        @AuraEnabled public String productId { get; set; }
        @AuraEnabled public String productName { get; set; }
        @AuraEnabled public String productCode { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal unitPrice { get; set; }
        @AuraEnabled public Decimal totalPrice { get; set; }
        @AuraEnabled public String description { get; set; }
    }
    
    /**
     * @description Wrapper class for payment request from Call Center
     */
    public class CallCenterPaymentRequest {
        @AuraEnabled public String accountId { get; set; }
        @AuraEnabled public List<CartItem> cartItems { get; set; }
        @AuraEnabled public String paymentMethodId { get; set; }
        @AuraEnabled public String paymentToken { get; set; }
        @AuraEnabled public String paymentType { get; set; } // Card or ACH
        @AuraEnabled public Boolean savePaymentMethod { get; set; }
        @AuraEnabled public String sourceDescription { get; set; }
        @AuraEnabled public String gatewayId { get; set; }
        // Card details (for new cards)
        @AuraEnabled public String cardLastFour { get; set; }
        @AuraEnabled public String cardType { get; set; }
        @AuraEnabled public String expirationMonth { get; set; }
        @AuraEnabled public String expirationYear { get; set; }
        // ACH details (for new ACH)
        @AuraEnabled public String bankName { get; set; }
        @AuraEnabled public String accountLastFour { get; set; }
        @AuraEnabled public String accountType { get; set; }
    }
    
    /**
     * @description Wrapper class for payment result
     */
    public class CallCenterPaymentResult {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String transactionId { get; set; }
        @AuraEnabled public String transactionNumber { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
    }
    
    /**
     * @description Search for accounts by name, phone, or email
     * @param searchTerm The search string (minimum 3 characters)
     * @return List of matching accounts
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> searchAccounts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 3) {
            return new List<Account>();
        }
        
        String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        
        return [
            SELECT Id, Name, Phone, BillingCity, BillingState,
                   (SELECT Id, pymtTest__Type__c, pymtTest__Last_Four__c, pymtTest__Expiration_Month__c,
                           pymtTest__Expiration_Year__c, pymtTest__Is_Primary__c, pymtTest__Active__c
                    FROM Payment_Methods__r
                    WHERE pymtTest__Active__c = true
                    ORDER BY pymtTest__Is_Primary__c DESC, CreatedDate DESC)
            FROM Account
            WHERE Name LIKE :searchPattern
               OR Phone LIKE :searchPattern
            ORDER BY Name
            LIMIT 20
        ];
    }
    
    /**
     * @description Create a new account with minimal fields (quick create)
     * @param accountName The account name
     * @param phone Phone number
     * @param email Email address
     * @return The created Account record
     */
    @AuraEnabled
    public static Account createQuickAccount(String accountName, String phone, String email) {
        if (String.isBlank(accountName)) {
            throw new AuraHandledException('Account name is required');
        }
        
        Account newAccount = new Account(
            Name = accountName,
            Phone = phone
        );
        
        try {
            insert newAccount;
            return [SELECT Id, Name, Phone FROM Account WHERE Id = :newAccount.Id];
        } catch (DmlException e) {
            throw new AuraHandledException('Error creating account: ' + e.getMessage());
        }
    }
    
    /**
     * @description Search for active products with pricing
     * @param searchTerm The search string
     * @return List of products with their standard prices
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> searchProducts(String searchTerm) {
        if (String.isBlank(searchTerm) || searchTerm.length() < 2) {
            return new List<Map<String, Object>>();
        }
        
        String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        
        // Get the standard pricebook
        Id standardPricebookId = getStandardPricebookId();
        
        List<PricebookEntry> entries = [
            SELECT Id, Product2Id, Product2.Name, Product2.ProductCode, 
                   Product2.Description, UnitPrice, Product2.IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :standardPricebookId
              AND Product2.IsActive = true
              AND IsActive = true
              AND (Product2.Name LIKE :searchPattern OR Product2.ProductCode LIKE :searchPattern)
            ORDER BY Product2.Name
            LIMIT 50
        ];
        
        List<Map<String, Object>> results = new List<Map<String, Object>>();
        for (PricebookEntry pbe : entries) {
            Map<String, Object> product = new Map<String, Object>();
            product.put('id', pbe.Product2Id);
            product.put('pricebookEntryId', pbe.Id);
            product.put('name', pbe.Product2.Name);
            product.put('productCode', pbe.Product2.ProductCode);
            product.put('description', pbe.Product2.Description);
            product.put('unitPrice', pbe.UnitPrice);
            results.add(product);
        }
        
        return results;
    }
    
    /**
     * @description Get saved payment methods for an account
     * @param accountId The account Id
     * @return List of active payment methods
     */
    @AuraEnabled(cacheable=true)
    public static List<pymtTest__Payment_Method__c> getPaymentMethods(String accountId) {
        if (String.isBlank(accountId)) {
            return new List<pymtTest__Payment_Method__c>();
        }
        
        return [
            SELECT Id, Name, pymtTest__Type__c, pymtTest__Last_Four__c, pymtTest__Expiration_Month__c,
                   pymtTest__Expiration_Year__c, pymtTest__Is_Primary__c, pymtTest__Card_Brand__c,
                   pymtTest__Active__c, pymtTest__Payment_Gateway__c, pymtTest__Gateway_Token__c
            FROM pymtTest__Payment_Method__c
            WHERE pymtTest__Account__c = :accountId
              AND pymtTest__Active__c = true
            ORDER BY pymtTest__Is_Primary__c DESC, CreatedDate DESC
        ];
    }
    
    /**
     * @description Process a Call Center payment with cart items
     * @param request The payment request containing cart and payment details
     * @return Payment result with transaction details
     */
    @AuraEnabled
    public static CallCenterPaymentResult processCallCenterPayment(CallCenterPaymentRequest request) {
        CallCenterPaymentResult result = new CallCenterPaymentResult();
        
        try {
            // Validate request
            validatePaymentRequest(request);
            
            // Calculate total from cart
            Decimal totalAmount = 0;
            for (CartItem item : request.cartItems) {
                totalAmount += item.quantity * item.unitPrice;
            }
            
            // Get or create payment method
            pymtTest__Payment_Method__c paymentMethod;
            if (String.isNotBlank(request.paymentMethodId)) {
                paymentMethod = [
                    SELECT Id, pymtTest__Gateway_Token__c, pymtTest__Payment_Gateway__c, pymtTest__Type__c
                    FROM pymtTest__Payment_Method__c
                    WHERE Id = :request.paymentMethodId
                ];
            } else if (String.isNotBlank(request.paymentToken)) {
                // Create new payment method if saving
                if (request.savePaymentMethod) {
                    paymentMethod = createPaymentMethod(request);
                }
            }
            
            // Get gateway
            String gatewayId = request.gatewayId;
            if (String.isBlank(gatewayId) && paymentMethod != null) {
                gatewayId = paymentMethod.pymtTest__Payment_Gateway__c;
            }
            if (String.isBlank(gatewayId)) {
                pymtTest__Payment_Gateway__c defaultGateway = [
                    SELECT Id
                    FROM pymtTest__Payment_Gateway__c
                    WHERE pymtTest__Is_Default__c = true AND pymtTest__Active__c = true
                    LIMIT 1
                ];
                gatewayId = defaultGateway.Id;
            }
            
            // Build payment request for gateway
            PaymentRequest paymentReq = new PaymentRequest();
            paymentReq.amount = totalAmount;
            paymentReq.paymentMethodToken = (paymentMethod != null) ? paymentMethod.pymtTest__Gateway_Token__c : request.paymentToken;
            paymentReq.idempotencyKey = generateIdempotencyKey();
            
            // Process payment through gateway
            PaymentGateway gateway = GatewayFactory.getGateway((Id) gatewayId);
            PaymentResponse response = gateway.sale(paymentReq);
            
            if (response.success) {
                // Create Transaction record
                pymtTest__Transaction__c txn = new pymtTest__Transaction__c(
                    pymtTest__Account__c = request.accountId,
                    pymtTest__Amount__c = totalAmount,
                    pymtTest__Status__c = 'Completed',
                    pymtTest__Type__c = 'Sale',
                    pymtTest__Payment_Type__c = request.paymentType == 'ACH' ? 'ACH' : 'Credit Card',
                    pymtTest__Sales_Channel__c = 'Phone',
                    pymtTest__Fulfillment_Status__c = 'Pending',
                    pymtTest__Source_Description__c = request.sourceDescription,
                    pymtTest__Gateway_Transaction_Id__c = response.transactionId,
                    pymtTest__Payment_Gateway__c = gatewayId,
                    pymtTest__Payment_Method__c = (paymentMethod != null) ? paymentMethod.Id : null,
                    pymtTest__Idempotency_Key__c = paymentReq.idempotencyKey,
                    pymtTest__Settlement_Status__c = request.paymentType == 'ACH' ? 'Pending' : 'Pending Settlement',
                    pymtTest__Expected_Settlement_Date__c = request.paymentType == 'ACH' 
                        ? Date.today().addDays(5) 
                        : Date.today().addDays(2)
                );
                insert txn;
                
                // Create Transaction Line Items
                List<pymtTest__Transaction_Line_Item__c> lineItems = new List<pymtTest__Transaction_Line_Item__c>();
                for (CartItem item : request.cartItems) {
                    pymtTest__Transaction_Line_Item__c lineItem = new pymtTest__Transaction_Line_Item__c(
                        pymtTest__Transaction__c = txn.Id,
                        pymtTest__Product__c = item.productId,
                        pymtTest__Quantity__c = item.quantity,
                        pymtTest__Unit_Price__c = item.unitPrice,
                        pymtTest__Description__c = item.description
                    );
                    lineItems.add(lineItem);
                }
                insert lineItems;
                
                // Enqueue Order/Invoice creation
                System.enqueueJob(new OrderFulfillmentQueueable(txn.Id));
                
                // Return success result
                result.success = true;
                result.transactionId = txn.Id;
                result.transactionNumber = [SELECT Name FROM pymtTest__Transaction__c WHERE Id = :txn.Id].Name;
                result.amount = totalAmount;
                
            } else {
                result.success = false;
                result.errorMessage = response.errorMessage;
            }
            
        } catch (Exception e) {
            result.success = false;
            result.errorMessage = e.getMessage();
        }
        
        return result;
    }
    
    /**
     * @description Validate the payment request
     */
    private static void validatePaymentRequest(CallCenterPaymentRequest request) {
        if (String.isBlank(request.accountId)) {
            throw new AuraHandledException('Account is required');
        }
        if (request.cartItems == null || request.cartItems.isEmpty()) {
            throw new AuraHandledException('Cart cannot be empty');
        }
        if (String.isBlank(request.paymentMethodId) && String.isBlank(request.paymentToken)) {
            throw new AuraHandledException('Payment method or token is required');
        }
    }
    
    /**
     * @description Create a new payment method from the request
     */
    private static pymtTest__Payment_Method__c createPaymentMethod(CallCenterPaymentRequest request) {
        String gatewayId = request.gatewayId;
        if (String.isBlank(gatewayId)) {
            pymtTest__Payment_Gateway__c defaultGateway = [
                SELECT Id
                FROM pymtTest__Payment_Gateway__c
                WHERE pymtTest__Is_Default__c = true AND pymtTest__Active__c = true
                LIMIT 1
            ];
            gatewayId = defaultGateway.Id;
        }
        
        pymtTest__Payment_Method__c pm = new pymtTest__Payment_Method__c(
            pymtTest__Account__c = request.accountId,
            pymtTest__Gateway_Token__c = request.paymentToken,
            pymtTest__Payment_Gateway__c = gatewayId,
            pymtTest__Active__c = true
        );
        
        if (request.paymentType == 'ACH') {
            pm.pymtTest__Type__c = 'ACH';
            pm.pymtTest__Last_Four__c = request.accountLastFour;
        } else {
            pm.pymtTest__Type__c = 'Credit Card';
            pm.pymtTest__Card_Brand__c = request.cardType;
            pm.pymtTest__Last_Four__c = request.cardLastFour;
            if (String.isNotBlank(request.expirationMonth) && String.isNotBlank(request.expirationYear)) {
                pm.pymtTest__Expiration_Year__c = Integer.valueOf(request.expirationYear);
                pm.pymtTest__Expiration_Month__c = Integer.valueOf(request.expirationMonth);
            }
        }
        
        insert pm;
        return pm;
    }
    
    /**
     * @description Get the standard pricebook Id
     */
    private static Id getStandardPricebookId() {
        if (Test.isRunningTest()) {
            return Test.getStandardPricebookId();
        }
        return [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
    }
    
    /**
     * @description Generate a unique idempotency key
     */
    private static String generateIdempotencyKey() {
        return 'CC-' + String.valueOf(DateTime.now().getTime()) + '-' + 
               String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}
