/**
 * @description Response object for payment transactions.
 * Contains the result of a payment operation.
 */
public class PaymentResponse {
    
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String transactionId { get; set; }
    @AuraEnabled public String status { get; set; }
    @AuraEnabled public Decimal amount { get; set; }
    @AuraEnabled public String currency_x { get; set; }
    @AuraEnabled public String errorCode { get; set; }
    @AuraEnabled public String errorMessage { get; set; }
    @AuraEnabled public String declineCode { get; set; }
    @AuraEnabled public String rawResponse { get; set; }
    @AuraEnabled public Map<String, Object> additionalData { get; set; }
    
    // Card details (masked)
    @AuraEnabled public String cardBrand { get; set; }
    @AuraEnabled public String cardLast4 { get; set; }
    @AuraEnabled public Integer cardExpMonth { get; set; }
    @AuraEnabled public Integer cardExpYear { get; set; }
    
    // For saved payment methods
    @AuraEnabled public String paymentMethodToken { get; set; }
    @AuraEnabled public String customerId { get; set; }
    
    // Timestamps
    @AuraEnabled public DateTime processedAt { get; set; }
    
    public PaymentResponse() {
        this.success = false;
        this.additionalData = new Map<String, Object>();
        this.processedAt = DateTime.now();
    }
    
    /**
     * @description Create a successful response
     * @param transactionId The gateway transaction ID
     * @param amount The transaction amount
     * @return PaymentResponse A success response
     */
    public static PaymentResponse success(String transactionId, Decimal amount) {
        PaymentResponse response = new PaymentResponse();
        response.success = true;
        response.transactionId = transactionId;
        response.amount = amount;
        response.status = 'Approved';
        return response;
    }
    
    /**
     * @description Create a failed response
     * @param errorCode The error code
     * @param errorMessage The error message
     * @return PaymentResponse A failure response
     */
    public static PaymentResponse failure(String errorCode, String errorMessage) {
        PaymentResponse response = new PaymentResponse();
        response.success = false;
        response.errorCode = errorCode;
        response.errorMessage = errorMessage;
        response.status = 'Declined';
        return response;
    }
    
    /**
     * @description Create an error response (system/gateway error)
     * @param errorMessage The error message
     * @return PaymentResponse An error response
     */
    public static PaymentResponse error(String errorMessage) {
        PaymentResponse response = new PaymentResponse();
        response.success = false;
        response.errorCode = 'SYSTEM_ERROR';
        response.errorMessage = errorMessage;
        response.status = 'Error';
        return response;
    }
}
