/**
 * @description Placetopay (Evertec) payment gateway implementation.
 * Implements the PaymentGateway interface for Placetopay API integration.
 * Supports credit cards, debit cards, ACH, and tokenization.
 * 
 * Placetopay is a leading payment gateway in Latin America operated by Evertec.
 * API Documentation: https://docs.placetopay.dev/
 */
public class PlacetopayGateway extends PaymentGatewayBase {
    
    private static final String LIVE_API_URL = 'https://checkout.placetopay.com/api';
    private static final String TEST_API_URL = 'https://checkout-test.placetopay.com/api';
    private static final String CLIENT_LIBRARY_URL = 'https://checkout.placetopay.com/js/checkout.js';
    
    // Placetopay-specific credentials
    private String login;
    private String tranKey;
    
    public PlacetopayGateway(Id gatewayId) {
        super(gatewayId);
        loadCredentials();
    }
    
    public PlacetopayGateway(pymts__Payment_Gateway__c gateway) {
        super(gateway);
        loadCredentials();
    }
    
    /**
     * @description Load Placetopay credentials from custom metadata
     */
    private void loadCredentials() {
        String metadataName = this.isTestMode ? 'Placetopay_Test' : 'Placetopay_Live';
        try {
            pymts__Gateway_Credential__mdt cred = [
                SELECT pymts__API_Login_Id__c, pymts__Transaction_Key__c
                FROM pymts__Gateway_Credential__mdt
                WHERE DeveloperName = :metadataName
                LIMIT 1
            ];
            this.login = cred.pymts__API_Login_Id__c;
            this.tranKey = cred.pymts__Transaction_Key__c;
        } catch (Exception e) {
            this.login = '';
            this.tranKey = '';
        }
    }
    
    /**
     * @description Get the gateway type identifier
     * @return String 'Placetopay'
     */
    public override String getGatewayType() {
        return 'Placetopay';
    }
    
    /**
     * @description Get the API base URL
     * @return String The Placetopay API URL
     */
    protected override String getApiBaseUrl() {
        return this.isTestMode ? TEST_API_URL : LIVE_API_URL;
    }
    
    /**
     * @description Get API key (not used for Placetopay - uses auth object)
     * @return String Empty string
     */
    protected override String getSecureApiKey() {
        return '';
    }
    
    /**
     * @description Set authorization header (Placetopay uses body auth)
     * @param request The HTTP request
     */
    protected override void setAuthorizationHeader(HttpRequest request) {
        // Placetopay uses auth object in request body, not header
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
    }
    
    /**
     * @description Get the JavaScript library URL for client-side integration
     * @return String The Placetopay checkout.js URL
     */
    public override String getClientLibraryUrl() {
        return CLIENT_LIBRARY_URL;
    }
    
    /**
     * @description Generate the auth object required by Placetopay API
     * Uses SHA-256 hash of nonce + seed + tranKey
     * @return Map<String, String> The auth object
     */
    private Map<String, Object> generateAuthObject() {
        String seed = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ssXXX');
        String rawNonce = String.valueOf(Datetime.now().getTime()) + String.valueOf(Math.random());
        String nonce = EncodingUtil.base64Encode(Blob.valueOf(rawNonce));
        
        // tranKey = Base64(SHA-256(nonce + seed + secretKey))
        String rawTranKey = rawNonce + seed + this.tranKey;
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(rawTranKey));
        String encodedTranKey = EncodingUtil.base64Encode(digest);
        
        Map<String, Object> auth = new Map<String, Object>();
        auth.put('login', this.login);
        auth.put('tranKey', encodedTranKey);
        auth.put('nonce', nonce);
        auth.put('seed', seed);
        
        return auth;
    }
    
    /**
     * @description Process a sale transaction (direct charge)
     * @param request The payment request
     * @return PaymentResponse The response
     */
    public override PaymentResponse sale(PaymentRequest request) {
        try {
            // Build the collect request for direct payment with token
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('auth', generateAuthObject());
            payload.put('locale', 'en_US');
            
            // Payment details
            Map<String, Object> payment = new Map<String, Object>();
            payment.put('reference', request.idempotencyKey);
            payment.put('description', String.isNotBlank(request.description) ? request.description : 'Payment');
            
            Map<String, Object> amount = new Map<String, Object>();
            amount.put('currency', request.currency_x);
            amount.put('total', request.amount);
            payment.put('amount', amount);
            
            payload.put('payment', payment);
            
            // Instrument (payment method token)
            if (String.isNotBlank(request.paymentMethodToken)) {
                Map<String, Object> instrument = new Map<String, Object>();
                Map<String, Object> token = new Map<String, Object>();
                token.put('token', request.paymentMethodToken);
                instrument.put('token', token);
                payload.put('instrument', instrument);
            }
            
            // Payer information
            if (String.isNotBlank(request.billingEmail)) {
                Map<String, Object> payer = new Map<String, Object>();
                payer.put('email', request.billingEmail);
                if (String.isNotBlank(request.billingName)) {
                    List<String> nameParts = request.billingName.split(' ', 2);
                    payer.put('name', nameParts[0]);
                    if (nameParts.size() > 1) {
                        payer.put('surname', nameParts[1]);
                    }
                }
                payload.put('payer', payer);
            }
            
            // IP Address for fraud prevention
            payload.put('ipAddress', '127.0.0.1');
            payload.put('userAgent', 'Salesforce/PlacetopayGateway');
            
            // Make API call
            HttpResponse response = makePlacetopayCallout('POST', '/collect', JSON.serialize(payload));
            
            return parseCollectResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Create a payment session for redirect flow
     * @param request The payment request
     * @return PaymentResponse Contains processUrl for redirect
     */
    public override PaymentResponse authorize(PaymentRequest request) {
        try {
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('auth', generateAuthObject());
            payload.put('locale', 'en_US');
            
            // Payment details
            Map<String, Object> payment = new Map<String, Object>();
            payment.put('reference', request.idempotencyKey);
            payment.put('description', String.isNotBlank(request.description) ? request.description : 'Authorization');
            
            Map<String, Object> amount = new Map<String, Object>();
            amount.put('currency', request.currency_x);
            amount.put('total', request.amount);
            payment.put('amount', amount);
            payment.put('allowPartial', false);
            
            payload.put('payment', payment);
            
            // Expiration (30 minutes from now)
            Datetime expiration = Datetime.now().addMinutes(30);
            payload.put('expiration', expiration.formatGmt('yyyy-MM-dd\'T\'HH:mm:ssXXX'));
            
            // Return URL
            payload.put('returnUrl', URL.getOrgDomainUrl().toExternalForm());
            
            // IP Address
            payload.put('ipAddress', '127.0.0.1');
            payload.put('userAgent', 'Salesforce/PlacetopayGateway');
            
            HttpResponse response = makePlacetopayCallout('POST', '/session', JSON.serialize(payload));
            
            return parseSessionResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Capture a previously authorized payment
     * Note: Placetopay typically uses direct capture, not auth-then-capture
     * @param transactionId The transaction ID to capture
     * @param amount The amount to capture
     * @return PaymentResponse The response
     */
    public override PaymentResponse capture(String transactionId, Decimal amount) {
        // Placetopay typically uses direct payment flow
        // This would need to be implemented based on specific Placetopay capture API
        return PaymentResponse.error('Capture not supported - use sale for direct payment');
    }
    
    /**
     * @description Process a refund (reverse transaction)
     * @param transactionId The internal reference of the transaction
     * @param amount The amount to refund
     * @return PaymentResponse The response
     */
    public override PaymentResponse refund(String transactionId, Decimal amount) {
        try {
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('auth', generateAuthObject());
            payload.put('internalReference', transactionId);
            
            Map<String, Object> action = new Map<String, Object>();
            action.put('action', 'reverse');
            if (amount != null && amount > 0) {
                Map<String, Object> amountObj = new Map<String, Object>();
                amountObj.put('total', amount);
                action.put('amount', amountObj);
            }
            payload.put('action', action);
            
            HttpResponse response = makePlacetopayCallout('POST', '/transaction', JSON.serialize(payload));
            
            return parseTransactionResponse(response, 'Refund');
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Void a transaction
     * @param transactionId The transaction ID to void
     * @return PaymentResponse The response
     */
    public override PaymentResponse voidTransaction(String transactionId) {
        try {
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('auth', generateAuthObject());
            payload.put('internalReference', transactionId);
            
            Map<String, Object> action = new Map<String, Object>();
            action.put('action', 'reverse');
            payload.put('action', action);
            
            HttpResponse response = makePlacetopayCallout('POST', '/transaction', JSON.serialize(payload));
            
            return parseTransactionResponse(response, 'Void');
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Create a payment token (instrument)
     * @param tokenRequest The token request
     * @return TokenResponse The response with token
     */
    public override TokenResponse createToken(TokenRequest tokenRequest) {
        try {
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('auth', generateAuthObject());
            payload.put('locale', 'en_US');
            
            // Payer information
            Map<String, Object> payer = new Map<String, Object>();
            if (String.isNotBlank(tokenRequest.cardholderName)) {
                List<String> nameParts = tokenRequest.cardholderName.split(' ', 2);
                payer.put('name', nameParts[0]);
                if (nameParts.size() > 1) {
                    payer.put('surname', nameParts[1]);
                }
            }
            payload.put('payer', payer);
            
            // Card instrument
            Map<String, Object> instrument = new Map<String, Object>();
            Map<String, Object> card = new Map<String, Object>();
            card.put('number', tokenRequest.cardNumber);
            card.put('expiration', tokenRequest.expirationMonth + '/' + tokenRequest.expirationYear.right(2));
            card.put('cvv', tokenRequest.cvv);
            instrument.put('card', card);
            payload.put('instrument', instrument);
            
            HttpResponse response = makePlacetopayCallout('POST', '/instrument/tokenize', JSON.serialize(payload));
            
            return parseTokenResponse(response);
            
        } catch (Exception e) {
            return TokenResponse.failure('TOKEN_ERROR', e.getMessage());
        }
    }
    
    /**
     * @description Create a customer profile
     * @param customerRequest The customer request
     * @return CustomerResponse The response
     */
    public override CustomerResponse createCustomer(CustomerRequest customerRequest) {
        // Placetopay doesn't have a separate customer API - customers are created with tokens
        return CustomerResponse.failure('NOT_SUPPORTED', 'Use tokenization - customer created with instrument');
    }
    
    /**
     * @description Attach a payment method to a customer
     * @param customerId The customer ID
     * @param paymentMethodToken The payment method token
     * @return PaymentMethodResponse The response
     */
    public override PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken) {
        // Placetopay tokens are standalone, not attached to customers
        return PaymentMethodResponse.failure('NOT_SUPPORTED', 'Placetopay tokens are standalone instruments');
    }
    
    /**
     * @description Query the status of a session
     * @param sessionId The session ID (requestId)
     * @return Map<String, Object> The session status
     */
    public Map<String, Object> getSessionStatus(String sessionId) {
        try {
            Map<String, Object> payload = new Map<String, Object>();
            payload.put('auth', generateAuthObject());
            
            HttpResponse response = makePlacetopayCallout('POST', '/session/' + sessionId, JSON.serialize(payload));
            
            if (response.getStatusCode() == 200) {
                return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            }
            return null;
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Make an API callout to Placetopay
     * @param method HTTP method
     * @param endpoint API endpoint
     * @param body Request body
     * @return HttpResponse The response
     */
    private HttpResponse makePlacetopayCallout(String method, String endpoint, String body) {
        HttpRequest request = new HttpRequest();
        request.setMethod(method);
        request.setEndpoint(getApiBaseUrl() + endpoint);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(120000);
        
        if (String.isNotBlank(body)) {
            request.setBody(body);
        }
        
        Http http = new Http();
        return http.send(request);
    }
    
    /**
     * @description Parse collect (direct payment) response
     */
    private PaymentResponse parseCollectResponse(HttpResponse response) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        
        Map<String, Object> status = (Map<String, Object>) result.get('status');
        String statusValue = (String) status.get('status');
        String message = (String) status.get('message');
        
        if (statusValue == 'APPROVED') {
            PaymentResponse paymentResponse = new PaymentResponse();
            paymentResponse.success = true;
            paymentResponse.transactionId = String.valueOf(result.get('internalReference'));
            paymentResponse.status = 'Approved';
            paymentResponse.rawResponse = response.getBody();
            paymentResponse.additionalData.put('message', message);
            paymentResponse.additionalData.put('authorization', (String) result.get('authorization'));
            
            // Extract payment details if available
            List<Object> paymentList = (List<Object>) result.get('payment');
            if (paymentList != null && !paymentList.isEmpty()) {
                Map<String, Object> payment = (Map<String, Object>) paymentList[0];
                paymentResponse.transactionId = String.valueOf(payment.get('internalReference'));
                paymentResponse.additionalData.put('authorization', (String) payment.get('authorization'));
                
                Map<String, Object> paymentStatus = (Map<String, Object>) payment.get('status');
                if (paymentStatus != null) {
                    paymentResponse.additionalData.put('message', (String) paymentStatus.get('message'));
                }
            }
            
            return paymentResponse;
            
        } else if (statusValue == 'PENDING') {
            PaymentResponse paymentResponse = new PaymentResponse();
            paymentResponse.success = true;
            paymentResponse.transactionId = String.valueOf(result.get('requestId'));
            paymentResponse.status = 'PENDING';
            paymentResponse.rawResponse = response.getBody();
            paymentResponse.additionalData.put('message', message);
            return paymentResponse;
            
        } else {
            String reason = (String) status.get('reason');
            return PaymentResponse.error(message + (String.isNotBlank(reason) ? ' (' + reason + ')' : ''));
        }
    }
    
    /**
     * @description Parse session creation response
     */
    private PaymentResponse parseSessionResponse(HttpResponse response) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        
        Map<String, Object> status = (Map<String, Object>) result.get('status');
        String statusValue = (String) status.get('status');
        
        if (statusValue == 'OK') {
            PaymentResponse paymentResponse = new PaymentResponse();
            paymentResponse.success = true;
            paymentResponse.transactionId = String.valueOf(result.get('requestId'));
            paymentResponse.status = 'PENDING';
            paymentResponse.rawResponse = response.getBody();
            paymentResponse.additionalData.put('processUrl', (String) result.get('processUrl'));
            return paymentResponse;
        } else {
            String message = (String) status.get('message');
            return PaymentResponse.error(message);
        }
    }
    
    /**
     * @description Parse transaction (refund/void) response
     */
    private PaymentResponse parseTransactionResponse(HttpResponse response, String actionType) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        
        Map<String, Object> status = (Map<String, Object>) result.get('status');
        String statusValue = (String) status.get('status');
        String message = (String) status.get('message');
        
        if (statusValue == 'APPROVED' || statusValue == 'OK') {
            PaymentResponse paymentResponse = new PaymentResponse();
            paymentResponse.success = true;
            paymentResponse.transactionId = String.valueOf(result.get('internalReference'));
            paymentResponse.status = 'Approved';
            paymentResponse.rawResponse = response.getBody();
            paymentResponse.additionalData.put('message', actionType + ' successful: ' + message);
            return paymentResponse;
        } else {
            return PaymentResponse.error(actionType + ' failed: ' + message);
        }
    }
    
    /**
     * @description Parse tokenization response
     */
    private TokenResponse parseTokenResponse(HttpResponse response) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        
        Map<String, Object> status = (Map<String, Object>) result.get('status');
        String statusValue = (String) status.get('status');
        
        if (statusValue == 'OK') {
            Map<String, Object> instrument = (Map<String, Object>) result.get('instrument');
            Map<String, Object> token = (Map<String, Object>) instrument.get('token');
            
            TokenResponse tokenResponse = new TokenResponse();
            tokenResponse.success = true;
            tokenResponse.token = (String) token.get('token');
            tokenResponse.last4 = (String) token.get('lastDigits');
            tokenResponse.cardBrand = (String) token.get('franchise');
            String validUntil = (String) token.get('validUntil');
            if (String.isNotBlank(validUntil) && validUntil.length() >= 7) {
                tokenResponse.expYear = Integer.valueOf(validUntil.substring(0, 4));
                tokenResponse.expMonth = Integer.valueOf(validUntil.substring(5, 7));
            }
            return tokenResponse;
        } else {
            String message = (String) status.get('message');
            return TokenResponse.failure('TOKEN_ERROR', message);
        }
    }
}
