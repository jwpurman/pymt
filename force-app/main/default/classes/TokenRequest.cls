/**
 * @description Request object for creating payment tokens
 */
public class TokenRequest {
    @AuraEnabled public String cardNumber { get; set; }
    @AuraEnabled public String expirationMonth { get; set; }
    @AuraEnabled public String expirationYear { get; set; }
    @AuraEnabled public String cvv { get; set; }
    @AuraEnabled public String cardholderName { get; set; }
    @AuraEnabled public String billingPostalCode { get; set; }
    
    // For bank accounts
    @AuraEnabled public String accountNumber { get; set; }
    @AuraEnabled public String routingNumber { get; set; }
    @AuraEnabled public String accountType { get; set; } // checking, savings
    @AuraEnabled public String accountHolderName { get; set; }
    
    public TokenRequest() {}
}
