/**
 * @description Braintree payment gateway implementation stub.
 */
public class BraintreeGateway extends PaymentGatewayBase {
    
    private static final String CLIENT_LIBRARY_URL = 'https://js.braintreegateway.com/web/dropin/1.33.0/js/dropin.min.js';
    
    public BraintreeGateway(Id gatewayId) { super(gatewayId); }
    public BraintreeGateway(pymtTest__Payment_Gateway__c gateway) { super(gateway); }
    
    public override String getGatewayType() { return 'Braintree'; }
    protected override String getApiBaseUrl() { return this.isTestMode ? 'https://api.sandbox.braintreegateway.com' : 'https://api.braintreegateway.com'; }
    protected override String getSecureApiKey() { return ''; }
    protected override void setAuthorizationHeader(HttpRequest request) { }
    public override String getClientLibraryUrl() { return CLIENT_LIBRARY_URL; }
    
    public override PaymentResponse sale(PaymentRequest request) { return PaymentResponse.error('Braintree gateway not yet implemented'); }
    public override PaymentResponse authorize(PaymentRequest request) { return PaymentResponse.error('Braintree gateway not yet implemented'); }
    public override PaymentResponse capture(String transactionId, Decimal amount) { return PaymentResponse.error('Braintree gateway not yet implemented'); }
    public override PaymentResponse refund(String transactionId, Decimal amount) { return PaymentResponse.error('Braintree gateway not yet implemented'); }
    public override PaymentResponse voidTransaction(String transactionId) { return PaymentResponse.error('Braintree gateway not yet implemented'); }
    public override TokenResponse createToken(TokenRequest tokenRequest) { return TokenResponse.failure('NOT_SUPPORTED', 'Use client-side tokenization'); }
    public override CustomerResponse createCustomer(CustomerRequest customerRequest) { return CustomerResponse.failure('NOT_IMPLEMENTED', 'Not yet implemented'); }
    public override PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken) { return PaymentMethodResponse.failure('NOT_IMPLEMENTED', 'Not yet implemented'); }
}
