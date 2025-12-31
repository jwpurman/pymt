/**
 * @description Response object for customer creation
 */
public class CustomerResponse {
    @AuraEnabled public Boolean success { get; set; }
    @AuraEnabled public String customerId { get; set; }
    @AuraEnabled public String errorCode { get; set; }
    @AuraEnabled public String errorMessage { get; set; }
    
    public CustomerResponse() {
        this.success = false;
    }
    
    public static CustomerResponse success(String customerId) {
        CustomerResponse response = new CustomerResponse();
        response.success = true;
        response.customerId = customerId;
        return response;
    }
    
    public static CustomerResponse failure(String errorCode, String errorMessage) {
        CustomerResponse response = new CustomerResponse();
        response.success = false;
        response.errorCode = errorCode;
        response.errorMessage = errorMessage;
        return response;
    }
}
