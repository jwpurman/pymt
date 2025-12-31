/**
 * @description Interface defining the contract for all payment gateway implementations.
 * All gateway implementations must implement this interface to ensure consistent behavior.
 */
public interface PaymentGateway {
    
    /**
     * @description Process a sale (charge) transaction
     * @param request The payment request containing amount, payment method, etc.
     * @return PaymentResponse The response from the gateway
     */
    PaymentResponse sale(PaymentRequest request);
    
    /**
     * @description Authorize a payment (hold funds without capturing)
     * @param request The payment request
     * @return PaymentResponse The response from the gateway
     */
    PaymentResponse authorize(PaymentRequest request);
    
    /**
     * @description Capture a previously authorized payment
     * @param transactionId The gateway transaction ID to capture
     * @param amount The amount to capture (can be less than authorized amount)
     * @return PaymentResponse The response from the gateway
     */
    PaymentResponse capture(String transactionId, Decimal amount);
    
    /**
     * @description Refund a transaction
     * @param transactionId The gateway transaction ID to refund
     * @param amount The amount to refund (can be partial)
     * @return PaymentResponse The response from the gateway
     */
    PaymentResponse refund(String transactionId, Decimal amount);
    
    /**
     * @description Void a transaction (cancel before settlement)
     * @param transactionId The gateway transaction ID to void
     * @return PaymentResponse The response from the gateway
     */
    PaymentResponse voidTransaction(String transactionId);
    
    /**
     * @description Create a token from a payment source (for PCI compliance)
     * @param tokenRequest The token request with payment source details
     * @return TokenResponse The response containing the token
     */
    TokenResponse createToken(TokenRequest tokenRequest);
    
    /**
     * @description Create a customer in the gateway's system
     * @param customerRequest The customer details
     * @return CustomerResponse The response containing the customer ID
     */
    CustomerResponse createCustomer(CustomerRequest customerRequest);
    
    /**
     * @description Attach a payment method to a customer
     * @param customerId The gateway customer ID
     * @param paymentMethodToken The payment method token
     * @return PaymentMethodResponse The response
     */
    PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken);
    
    /**
     * @description Get the gateway type
     * @return String The gateway type identifier
     */
    String getGatewayType();
    
    /**
     * @description Validate the gateway configuration
     * @return Boolean True if configuration is valid
     */
    Boolean validateConfiguration();
    
    /**
     * @description Get the JavaScript library URL for client-side tokenization
     * @return String The URL of the gateway's JavaScript library
     */
    String getClientLibraryUrl();
    
    /**
     * @description Get the public key for client-side tokenization
     * @return String The public/publishable key
     */
    String getPublicKey();
}
