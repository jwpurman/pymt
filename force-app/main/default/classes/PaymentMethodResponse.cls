/**
 * @description Response object for payment method operations
 */
public class PaymentMethodResponse {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String paymentMethodId { get; set; }
    @AuraEnabled public String cardBrand { get; set; }
    @AuraEnabled public String last4 { get; set; }
    @AuraEnabled public Integer expMonth { get; set; }
    @AuraEnabled public Integer expYear { get; set; }
    @AuraEnabled public String errorCode { get; set; }
    @AuraEnabled public String errorMessage { get; set; }
    
    public PaymentMethodResponse() {
        this.success = false;
    }
    
    public static PaymentMethodResponse success(String paymentMethodId) {
        PaymentMethodResponse response = new PaymentMethodResponse();
        response.success = true;
        response.paymentMethodId = paymentMethodId;
        return response;
    }
    
    public static PaymentMethodResponse failure(String errorCode, String errorMessage) {
        PaymentMethodResponse response = new PaymentMethodResponse();
        response.success = false;
        response.errorCode = errorCode;
        response.errorMessage = errorMessage;
        return response;
    }
}
