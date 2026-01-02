/**
 * @description PayPal payment gateway implementation stub.
 */
public class PayPalGateway extends PaymentGatewayBase {
    
    private static final String CLIENT_LIBRARY_URL = 'https://www.paypal.com/sdk/js';
    
    public PayPalGateway(Id gatewayId) { super(gatewayId); }
    public PayPalGateway(pymts__Payment_Gateway__c gateway) { super(gateway); }
    
    public override String getGatewayType() { return 'PayPal'; }
    protected override String getApiBaseUrl() { return this.isTestMode ? 'https://api-m.sandbox.paypal.com' : 'https://api-m.paypal.com'; }
    protected override String getSecureApiKey() { return ''; }
    protected override void setAuthorizationHeader(HttpRequest request) { }
    public override String getClientLibraryUrl() { return CLIENT_LIBRARY_URL; }
    
    public override PaymentResponse sale(PaymentRequest request) { return PaymentResponse.error('PayPal gateway not yet implemented'); }
    public override PaymentResponse authorize(PaymentRequest request) { return PaymentResponse.error('PayPal gateway not yet implemented'); }
    public override PaymentResponse capture(String transactionId, Decimal amount) { return PaymentResponse.error('PayPal gateway not yet implemented'); }
    public override PaymentResponse refund(String transactionId, Decimal amount) { return PaymentResponse.error('PayPal gateway not yet implemented'); }
    public override PaymentResponse voidTransaction(String transactionId) { return PaymentResponse.error('PayPal gateway not yet implemented'); }
    public override TokenResponse createToken(TokenRequest tokenRequest) { return TokenResponse.failure('NOT_SUPPORTED', 'Use client-side tokenization'); }
    public override CustomerResponse createCustomer(CustomerRequest customerRequest) { return CustomerResponse.failure('NOT_IMPLEMENTED', 'Not yet implemented'); }
    public override PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken) { return PaymentMethodResponse.failure('NOT_IMPLEMENTED', 'Not yet implemented'); }
}
