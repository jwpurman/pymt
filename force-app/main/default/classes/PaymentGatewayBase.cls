/**
 * @description Abstract base class for payment gateway implementations.
 * Provides common functionality and helper methods for all gateways.
 */
public abstract class PaymentGatewayBase implements PaymentGateway {
    
    protected pymts__Payment_Gateway__c gatewayConfig;
    protected String apiKey;
    protected String publicKey;
    protected Boolean isTestMode;
    
    /**
     * @description Constructor that loads gateway configuration
     * @param gatewayId The Salesforce ID of the Payment Gateway record
     */
    public PaymentGatewayBase(Id gatewayId) {
        loadConfiguration(gatewayId);
    }
    
    /**
     * @description Constructor with gateway record
     * @param gateway The Payment Gateway record
     */
    public PaymentGatewayBase(pymts__Payment_Gateway__c gateway) {
        this.gatewayConfig = gateway;
        initializeFromConfig();
    }
    
    /**
     * @description Load gateway configuration from database
     * @param gatewayId The gateway record ID
     */
    protected virtual void loadConfiguration(Id gatewayId) {
        this.gatewayConfig = [
            SELECT Id, Name, pymts__Gateway_Type__c, pymts__Active__c,
                   pymts__Environment__c, pymts__Public_Key__c, pymts__Is_Default__c
            FROM pymts__Payment_Gateway__c
            WHERE Id = :gatewayId
            LIMIT 1
        ];
        initializeFromConfig();
    }
    
    /**
     * @description Initialize instance variables from configuration
     */
    protected virtual void initializeFromConfig() {
        this.isTestMode = this.gatewayConfig.pymts__Environment__c == 'Test';
        this.publicKey = this.gatewayConfig.pymts__Public_Key__c;
        // API key should be loaded from Named Credential or Protected Custom Metadata
        this.apiKey = getSecureApiKey();
    }
    
    /**
     * @description Get API key from secure storage
     * Override in subclass for gateway-specific implementation
     * @return String The API key
     */
    protected abstract String getSecureApiKey();
    
    /**
     * @description Get the base URL for API calls
     * @return String The API base URL
     */
    protected abstract String getApiBaseUrl();
    
    /**
     * @description Make an HTTP callout to the gateway
     * @param method The HTTP method (GET, POST, etc.)
     * @param endpoint The API endpoint
     * @param body The request body (for POST/PUT)
     * @return HttpResponse The response from the gateway
     */
    protected HttpResponse makeCallout(String method, String endpoint, String body) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        request.setEndpoint(getApiBaseUrl() + endpoint);
        request.setMethod(method);
        request.setTimeout(120000); // 2 minutes
        
        // Set headers
        setAuthorizationHeader(request);
        request.setHeader('Content-Type', 'application/json');
        
        if (String.isNotBlank(body)) {
            request.setBody(body);
        }
        
        // Log the request (mask sensitive data)
        logRequest(method, endpoint, body);
        
        HttpResponse response;
        try {
            response = http.send(request);
            logResponse(response);
        } catch (Exception e) {
            throw new PaymentGatewayException('Gateway communication error: ' + e.getMessage());
        }
        
        return response;
    }
    
    /**
     * @description Set the authorization header for API calls
     * @param request The HTTP request
     */
    protected abstract void setAuthorizationHeader(HttpRequest request);
    
    /**
     * @description Log API request (for debugging/audit)
     */
    protected virtual void logRequest(String method, String endpoint, String body) {
        // Implement audit logging here
        System.debug(LoggingLevel.INFO, 'Gateway Request: ' + method + ' ' + endpoint);
    }
    
    /**
     * @description Log API response (for debugging/audit)
     */
    protected virtual void logResponse(HttpResponse response) {
        System.debug(LoggingLevel.INFO, 'Gateway Response: ' + response.getStatusCode());
    }
    
    /**
     * @description Validate the gateway configuration
     * @return Boolean True if valid
     */
    public virtual Boolean validateConfiguration() {
        return this.gatewayConfig != null 
            && this.gatewayConfig.pymts__Active__c 
            && String.isNotBlank(this.apiKey);
    }
    
    /**
     * @description Get the public key for client-side tokenization
     * @return String The public key
     */
    public virtual String getPublicKey() {
        return this.publicKey;
    }
    
    /**
     * @description Get the gateway type identifier
     * @return String The gateway type
     */
    public abstract String getGatewayType();
    
    /**
     * @description Get the client library URL for tokenization
     * @return String The JavaScript library URL
     */
    public abstract String getClientLibraryUrl();
    
    /**
     * @description Process a sale transaction
     * @param request The payment request
     * @return PaymentResponse The response
     */
    public abstract PaymentResponse sale(PaymentRequest request);
    
    /**
     * @description Authorize a payment
     * @param request The payment request
     * @return PaymentResponse The response
     */
    public abstract PaymentResponse authorize(PaymentRequest request);
    
    /**
     * @description Capture a previously authorized payment
     * @param transactionId The transaction ID
     * @param amount The amount to capture
     * @return PaymentResponse The response
     */
    public abstract PaymentResponse capture(String transactionId, Decimal amount);
    
    /**
     * @description Refund a transaction
     * @param transactionId The transaction ID
     * @param amount The amount to refund
     * @return PaymentResponse The response
     */
    public abstract PaymentResponse refund(String transactionId, Decimal amount);
    
    /**
     * @description Void a transaction
     * @param transactionId The transaction ID
     * @return PaymentResponse The response
     */
    public abstract PaymentResponse voidTransaction(String transactionId);
    
    /**
     * @description Create a token
     * @param tokenRequest The token request
     * @return TokenResponse The response
     */
    public abstract TokenResponse createToken(TokenRequest tokenRequest);
    
    /**
     * @description Create a customer
     * @param customerRequest The customer request
     * @return CustomerResponse The response
     */
    public abstract CustomerResponse createCustomer(CustomerRequest customerRequest);
    
    /**
     * @description Attach a payment method to a customer
     * @param customerId The customer ID
     * @param paymentMethodToken The payment method token
     * @return PaymentMethodResponse The response
     */
    public abstract PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken);
    
    /**
     * @description Convert amount to gateway format (cents for most gateways)
     * @param amount The amount in dollars
     * @return Integer The amount in cents
     */
    protected Integer convertToCents(Decimal amount) {
        return (amount * 100).intValue();
    }
    
    /**
     * @description Convert amount from gateway format (cents) to dollars
     * @param cents The amount in cents
     * @return Decimal The amount in dollars
     */
    protected Decimal convertFromCents(Integer cents) {
        return Decimal.valueOf(cents) / 100;
    }
    
    /**
     * @description Parse card brand from BIN/IIN
     * @param cardNumber The card number (at least first 6 digits)
     * @return String The card brand
     */
    protected String detectCardBrand(String cardNumber) {
        if (String.isBlank(cardNumber) || cardNumber.length() < 4) {
            return 'Unknown';
        }
        
        String cleaned = cardNumber.replaceAll('[^0-9]', '');
        
        if (cleaned.startsWith('4')) {
            return 'Visa';
        } else if (cleaned.startsWith('5') || 
                   (cleaned.length() >= 4 && Integer.valueOf(cleaned.substring(0, 4)) >= 2221 && 
                    Integer.valueOf(cleaned.substring(0, 4)) <= 2720)) {
            return 'Mastercard';
        } else if (cleaned.startsWith('34') || cleaned.startsWith('37')) {
            return 'American Express';
        } else if (cleaned.startsWith('6011') || cleaned.startsWith('65') || 
                   cleaned.startsWith('644') || cleaned.startsWith('645') || 
                   cleaned.startsWith('646') || cleaned.startsWith('647') || 
                   cleaned.startsWith('648') || cleaned.startsWith('649')) {
            return 'Discover';
        } else if (cleaned.startsWith('36') || cleaned.startsWith('38') || 
                   cleaned.startsWith('30')) {
            return 'Diners Club';
        } else if (cleaned.startsWith('35')) {
            return 'JCB';
        } else if (cleaned.startsWith('62')) {
            return 'UnionPay';
        }
        
        return 'Unknown';
    }
    
    /**
     * @description Custom exception for gateway errors
     */
    public class PaymentGatewayException extends Exception {}
}
