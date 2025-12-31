/**
 * @description Request object for payment transactions.
 * Contains all information needed to process a payment.
 */
public class PaymentRequest {
    
    @AuraEnabled public Decimal amount { get; set; }
    @AuraEnabled public String currency_x { get; set; } // 'currency' is reserved
    @AuraEnabled public String paymentMethodToken { get; set; }
    @AuraEnabled public String customerId { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public String idempotencyKey { get; set; }
    @AuraEnabled public Map<String, String> metadata { get; set; }
    
    // Billing information
    @AuraEnabled public String billingName { get; set; }
    @AuraEnabled public String billingEmail { get; set; }
    @AuraEnabled public String billingPhone { get; set; }
    @AuraEnabled public String billingStreet { get; set; }
    @AuraEnabled public String billingCity { get; set; }
    @AuraEnabled public String billingState { get; set; }
    @AuraEnabled public String billingPostalCode { get; set; }
    @AuraEnabled public String billingCountry { get; set; }
    
    // Salesforce references
    @AuraEnabled public Id accountId { get; set; }
    @AuraEnabled public Id invoiceId { get; set; }
    @AuraEnabled public Id paymentMethodId { get; set; }
    @AuraEnabled public Id gatewayId { get; set; }
    
    // For new card payments (tokenized client-side)
    @AuraEnabled public String cardToken { get; set; }
    @AuraEnabled public Boolean savePaymentMethod { get; set; }
    @AuraEnabled public Boolean setAsPrimary { get; set; }
    
    public PaymentRequest() {
        this.currency_x = 'USD';
        this.metadata = new Map<String, String>();
        this.savePaymentMethod = false;
        this.setAsPrimary = false;
    }
    
    /**
     * @description Generate an idempotency key if not provided
     * @return String The idempotency key
     */
    public String getOrGenerateIdempotencyKey() {
        if (String.isBlank(this.idempotencyKey)) {
            this.idempotencyKey = generateIdempotencyKey();
        }
        return this.idempotencyKey;
    }
    
    /**
     * @description Generate a unique idempotency key
     * @return String A unique key
     */
    private String generateIdempotencyKey() {
        Blob b = Crypto.generateAesKey(128);
        return EncodingUtil.convertToHex(b);
    }
    
    /**
     * @description Validate the request has required fields
     * @return List<String> List of validation errors, empty if valid
     */
    public List<String> validate() {
        List<String> errors = new List<String>();
        
        if (this.amount == null || this.amount <= 0) {
            errors.add('Amount must be greater than zero');
        }
        
        if (String.isBlank(this.paymentMethodToken) && String.isBlank(this.cardToken)) {
            errors.add('Payment method token or card token is required');
        }
        
        return errors;
    }
}
