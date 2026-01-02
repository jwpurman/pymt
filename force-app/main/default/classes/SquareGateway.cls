/**
 * @description Square payment gateway implementation stub.
 */
public class SquareGateway extends PaymentGatewayBase {
    
    private static final String CLIENT_LIBRARY_URL = 'https://sandbox.web.squarecdn.com/v1/square.js';
    
    public SquareGateway(Id gatewayId) { super(gatewayId); }
    public SquareGateway(pymts__Payment_Gateway__c gateway) { super(gateway); }
    
    public override String getGatewayType() { return 'Square'; }
    protected override String getApiBaseUrl() { return this.isTestMode ? 'https://connect.squareupsandbox.com/v2' : 'https://connect.squareup.com/v2'; }
    protected override String getSecureApiKey() { return ''; }
    protected override void setAuthorizationHeader(HttpRequest request) { request.setHeader('Authorization', 'Bearer ' + this.apiKey); }
    public override String getClientLibraryUrl() { return CLIENT_LIBRARY_URL; }
    
    public override PaymentResponse sale(PaymentRequest request) { return PaymentResponse.error('Square gateway not yet implemented'); }
    public override PaymentResponse authorize(PaymentRequest request) { return PaymentResponse.error('Square gateway not yet implemented'); }
    public override PaymentResponse capture(String transactionId, Decimal amount) { return PaymentResponse.error('Square gateway not yet implemented'); }
    public override PaymentResponse refund(String transactionId, Decimal amount) { return PaymentResponse.error('Square gateway not yet implemented'); }
    public override PaymentResponse voidTransaction(String transactionId) { return PaymentResponse.error('Square gateway not yet implemented'); }
    public override TokenResponse createToken(TokenRequest tokenRequest) { return TokenResponse.failure('NOT_SUPPORTED', 'Use client-side tokenization'); }
    public override CustomerResponse createCustomer(CustomerRequest customerRequest) { return CustomerResponse.failure('NOT_IMPLEMENTED', 'Not yet implemented'); }
    public override PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken) { return PaymentMethodResponse.failure('NOT_IMPLEMENTED', 'Not yet implemented'); }
}
