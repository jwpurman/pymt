/**
 * @description Request object for creating customers in the payment gateway
 */
public class CustomerRequest {
    @AuraEnabled public String email { get; set; }
    @AuraEnabled public String name { get; set; }
    @AuraEnabled public String phone { get; set; }
    @AuraEnabled public String description { get; set; }
    @AuraEnabled public Map<String, String> metadata { get; set; }
    @AuraEnabled public Id accountId { get; set; }
    
    public CustomerRequest() {
        this.metadata = new Map<String, String>();
    }
}
