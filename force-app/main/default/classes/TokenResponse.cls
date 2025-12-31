/**
 * @description Response object for token creation
 */
public class TokenResponse {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String token { get; set; }
    @AuraEnabled public String cardBrand { get; set; }
    @AuraEnabled public String last4 { get; set; }
    @AuraEnabled public Integer expMonth { get; set; }
    @AuraEnabled public Integer expYear { get; set; }
    @AuraEnabled public String errorCode { get; set; }
    @AuraEnabled public String errorMessage { get; set; }
    
    public TokenResponse() {
        this.success = false;
    }
    
    public static TokenResponse success(String token) {
        TokenResponse response = new TokenResponse();
        response.success = true;
        response.token = token;
        return response;
    }
    
    public static TokenResponse failure(String errorCode, String errorMessage) {
        TokenResponse response = new TokenResponse();
        response.success = false;
        response.errorCode = errorCode;
        response.errorMessage = errorMessage;
        return response;
    }
}
