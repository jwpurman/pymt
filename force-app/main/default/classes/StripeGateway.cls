/**
 * @description Stripe payment gateway implementation.
 * Implements the PaymentGateway interface for Stripe API integration.
 */
public class StripeGateway extends PaymentGatewayBase {
    
    private static final String LIVE_API_URL = 'https://api.stripe.com/v1';
    private static final String TEST_API_URL = 'https://api.stripe.com/v1';
    private static final String CLIENT_LIBRARY_URL = 'https://js.stripe.com/v3/';
    
    public StripeGateway(Id gatewayId) {
        super(gatewayId);
    }
    
    public StripeGateway(pymts__Payment_Gateway__c gateway) {
        super(gateway);
    }
    
    /**
     * @description Get the gateway type identifier
     * @return String 'Stripe'
     */
    public override String getGatewayType() {
        return 'Stripe';
    }
    
    /**
     * @description Get the API base URL
     * @return String The Stripe API URL
     */
    protected override String getApiBaseUrl() {
        return this.isTestMode ? TEST_API_URL : LIVE_API_URL;
    }
    
    /**
     * @description Get API key from Named Credential
     * @return String The API key
     */
    protected override String getSecureApiKey() {
        // In production, use Named Credentials or Protected Custom Metadata
        // For this example, we'll use a custom metadata type
        return getApiKeyFromMetadata();
    }
    
    /**
     * @description Get API key from custom metadata
     * @return String The API key
     */
    private String getApiKeyFromMetadata() {
        // This should be implemented using Protected Custom Metadata Type
        // For now, return placeholder - in real implementation, query metadata
        String metadataKey = this.isTestMode ? 'Stripe_Test_Key' : 'Stripe_Live_Key';
        // Query custom metadata and return key
        return ''; // Placeholder
    }
    
    /**
     * @description Set Stripe authorization header
     * @param request The HTTP request
     */
    protected override void setAuthorizationHeader(HttpRequest request) {
        String credentials = EncodingUtil.base64Encode(Blob.valueOf(this.apiKey + ':'));
        request.setHeader('Authorization', 'Basic ' + credentials);
    }
    
    /**
     * @description Get the JavaScript library URL
     * @return String The Stripe.js URL
     */
    public override String getClientLibraryUrl() {
        return CLIENT_LIBRARY_URL;
    }
    
    /**
     * @description Process a sale transaction
     * @param request The payment request
     * @return PaymentResponse The response
     */
    public override PaymentResponse sale(PaymentRequest request) {
        try {
            // Build the request body
            Map<String, String> params = new Map<String, String>();
            params.put('amount', String.valueOf(convertToCents(request.amount)));
            params.put('currency', request.currency_x.toLowerCase());
            params.put('confirm', 'true');
            
            // Use payment method token or create from card token
            if (String.isNotBlank(request.paymentMethodToken)) {
                params.put('payment_method', request.paymentMethodToken);
            }
            
            if (String.isNotBlank(request.customerId)) {
                params.put('customer', request.customerId);
            }
            
            if (String.isNotBlank(request.description)) {
                params.put('description', request.description);
            }
            
            if (String.isNotBlank(request.idempotencyKey)) {
                // Idempotency key is sent as header in Stripe
            }
            
            // Add metadata
            if (request.metadata != null) {
                for (String key : request.metadata.keySet()) {
                    params.put('metadata[' + key + ']', request.metadata.get(key));
                }
            }
            
            // Make the API call
            String body = buildFormEncodedBody(params);
            HttpResponse response = makeStripeCallout('POST', '/payment_intents', body, request.idempotencyKey);
            
            return parsePaymentIntentResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Authorize a payment
     * @param request The payment request
     * @return PaymentResponse The response
     */
    public override PaymentResponse authorize(PaymentRequest request) {
        try {
            Map<String, String> params = new Map<String, String>();
            params.put('amount', String.valueOf(convertToCents(request.amount)));
            params.put('currency', request.currency_x.toLowerCase());
            params.put('capture_method', 'manual'); // Don't capture yet
            params.put('confirm', 'true');
            
            if (String.isNotBlank(request.paymentMethodToken)) {
                params.put('payment_method', request.paymentMethodToken);
            }
            
            if (String.isNotBlank(request.customerId)) {
                params.put('customer', request.customerId);
            }
            
            String body = buildFormEncodedBody(params);
            HttpResponse response = makeStripeCallout('POST', '/payment_intents', body, request.idempotencyKey);
            
            return parsePaymentIntentResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Capture a previously authorized payment
     * @param transactionId The PaymentIntent ID
     * @param amount The amount to capture
     * @return PaymentResponse The response
     */
    public override PaymentResponse capture(String transactionId, Decimal amount) {
        try {
            Map<String, String> params = new Map<String, String>();
            if (amount != null) {
                params.put('amount_to_capture', String.valueOf(convertToCents(amount)));
            }
            
            String body = buildFormEncodedBody(params);
            HttpResponse response = makeStripeCallout('POST', '/payment_intents/' + transactionId + '/capture', body, null);
            
            return parsePaymentIntentResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Refund a transaction
     * @param transactionId The PaymentIntent ID
     * @param amount The amount to refund
     * @return PaymentResponse The response
     */
    public override PaymentResponse refund(String transactionId, Decimal amount) {
        try {
            Map<String, String> params = new Map<String, String>();
            params.put('payment_intent', transactionId);
            
            if (amount != null) {
                params.put('amount', String.valueOf(convertToCents(amount)));
            }
            
            String body = buildFormEncodedBody(params);
            HttpResponse response = makeStripeCallout('POST', '/refunds', body, null);
            
            return parseRefundResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Void/cancel a transaction
     * @param transactionId The PaymentIntent ID
     * @return PaymentResponse The response
     */
    public override PaymentResponse voidTransaction(String transactionId) {
        try {
            HttpResponse response = makeStripeCallout('POST', '/payment_intents/' + transactionId + '/cancel', '', null);
            return parsePaymentIntentResponse(response);
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Create a token (Note: Should be done client-side with Stripe.js)
     * @param tokenRequest The token request
     * @return TokenResponse The response
     */
    public override TokenResponse createToken(TokenRequest tokenRequest) {
        // This should be done client-side with Stripe.js for PCI compliance
        return TokenResponse.failure('NOT_SUPPORTED', 
            'Card tokenization must be done client-side using Stripe.js');
    }
    
    /**
     * @description Create a customer in Stripe
     * @param customerRequest The customer request
     * @return CustomerResponse The response
     */
    public override CustomerResponse createCustomer(CustomerRequest customerRequest) {
        try {
            Map<String, String> params = new Map<String, String>();
            
            if (String.isNotBlank(customerRequest.email)) {
                params.put('email', customerRequest.email);
            }
            if (String.isNotBlank(customerRequest.name)) {
                params.put('name', customerRequest.name);
            }
            if (String.isNotBlank(customerRequest.phone)) {
                params.put('phone', customerRequest.phone);
            }
            if (String.isNotBlank(customerRequest.description)) {
                params.put('description', customerRequest.description);
            }
            
            // Add metadata
            if (customerRequest.metadata != null) {
                for (String key : customerRequest.metadata.keySet()) {
                    params.put('metadata[' + key + ']', customerRequest.metadata.get(key));
                }
            }
            
            // Add Salesforce Account ID to metadata
            if (customerRequest.accountId != null) {
                params.put('metadata[salesforce_account_id]', customerRequest.accountId);
            }
            
            String body = buildFormEncodedBody(params);
            HttpResponse response = makeStripeCallout('POST', '/customers', body, null);
            
            return parseCustomerResponse(response);
            
        } catch (Exception e) {
            return CustomerResponse.failure('SYSTEM_ERROR', e.getMessage());
        }
    }
    
    /**
     * @description Attach a payment method to a customer
     * @param customerId The Stripe customer ID
     * @param paymentMethodToken The payment method token
     * @return PaymentMethodResponse The response
     */
    public override PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken) {
        try {
            Map<String, String> params = new Map<String, String>();
            params.put('customer', customerId);
            
            String body = buildFormEncodedBody(params);
            HttpResponse response = makeStripeCallout('POST', '/payment_methods/' + paymentMethodToken + '/attach', body, null);
            
            return parsePaymentMethodResponse(response);
            
        } catch (Exception e) {
            return PaymentMethodResponse.failure('SYSTEM_ERROR', e.getMessage());
        }
    }
    
    /**
     * @description Make a Stripe-specific callout with proper headers
     */
    private HttpResponse makeStripeCallout(String method, String endpoint, String body, String idempotencyKey) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        request.setEndpoint(getApiBaseUrl() + endpoint);
        request.setMethod(method);
        request.setTimeout(120000);
        
        // Stripe-specific headers
        setAuthorizationHeader(request);
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        request.setHeader('Stripe-Version', '2023-10-16');
        
        if (String.isNotBlank(idempotencyKey)) {
            request.setHeader('Idempotency-Key', idempotencyKey);
        }
        
        if (String.isNotBlank(body)) {
            request.setBody(body);
        }
        
        return http.send(request);
    }
    
    /**
     * @description Build form-encoded body for Stripe API
     */
    private String buildFormEncodedBody(Map<String, String> params) {
        List<String> pairs = new List<String>();
        for (String key : params.keySet()) {
            String value = params.get(key);
            if (String.isNotBlank(value)) {
                pairs.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + 
                         EncodingUtil.urlEncode(value, 'UTF-8'));
            }
        }
        return String.join(pairs, '&');
    }
    
    /**
     * @description Parse PaymentIntent response from Stripe
     */
    private PaymentResponse parsePaymentIntentResponse(HttpResponse response) {
        PaymentResponse result = new PaymentResponse();
        
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        result.rawResponse = response.getBody();
        
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            result.success = true;
            result.transactionId = (String) jsonResponse.get('id');
            
            Integer amountCents = (Integer) jsonResponse.get('amount');
            result.amount = convertFromCents(amountCents);
            result.currency_x = (String) jsonResponse.get('currency');
            
            String status = (String) jsonResponse.get('status');
            result.status = mapStripeStatus(status);
            
            // Get payment method details if available
            if (jsonResponse.containsKey('payment_method')) {
                Object pmObj = jsonResponse.get('payment_method');
                if (pmObj instanceof String) {
                    result.paymentMethodToken = (String) pmObj;
                } else if (pmObj instanceof Map<String, Object>) {
                    Map<String, Object> pm = (Map<String, Object>) pmObj;
                    result.paymentMethodToken = (String) pm.get('id');
                    
                    if (pm.containsKey('card')) {
                        Map<String, Object> card = (Map<String, Object>) pm.get('card');
                        result.cardBrand = (String) card.get('brand');
                        result.cardLast4 = (String) card.get('last4');
                        result.cardExpMonth = (Integer) card.get('exp_month');
                        result.cardExpYear = (Integer) card.get('exp_year');
                    }
                }
            }
            
        } else {
            result.success = false;
            
            if (jsonResponse.containsKey('error')) {
                Map<String, Object> error = (Map<String, Object>) jsonResponse.get('error');
                result.errorCode = (String) error.get('code');
                result.errorMessage = (String) error.get('message');
                result.declineCode = (String) error.get('decline_code');
            }
            
            result.status = 'Declined';
        }
        
        return result;
    }
    
    /**
     * @description Parse refund response from Stripe
     */
    private PaymentResponse parseRefundResponse(HttpResponse response) {
        PaymentResponse result = new PaymentResponse();
        
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        result.rawResponse = response.getBody();
        
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            result.success = true;
            result.transactionId = (String) jsonResponse.get('id');
            
            Integer amountCents = (Integer) jsonResponse.get('amount');
            result.amount = convertFromCents(amountCents);
            result.status = 'Refunded';
            
        } else {
            result.success = false;
            
            if (jsonResponse.containsKey('error')) {
                Map<String, Object> error = (Map<String, Object>) jsonResponse.get('error');
                result.errorCode = (String) error.get('code');
                result.errorMessage = (String) error.get('message');
            }
            
            result.status = 'Error';
        }
        
        return result;
    }
    
    /**
     * @description Parse customer response from Stripe
     */
    private CustomerResponse parseCustomerResponse(HttpResponse response) {
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            return CustomerResponse.success((String) jsonResponse.get('id'));
        } else {
            String errorMessage = 'Unknown error';
            String errorCode = 'UNKNOWN';
            
            if (jsonResponse.containsKey('error')) {
                Map<String, Object> error = (Map<String, Object>) jsonResponse.get('error');
                errorCode = (String) error.get('code');
                errorMessage = (String) error.get('message');
            }
            
            return CustomerResponse.failure(errorCode, errorMessage);
        }
    }
    
    /**
     * @description Parse payment method response from Stripe
     */
    private PaymentMethodResponse parsePaymentMethodResponse(HttpResponse response) {
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        
        if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
            PaymentMethodResponse result = PaymentMethodResponse.success((String) jsonResponse.get('id'));
            
            if (jsonResponse.containsKey('card')) {
                Map<String, Object> card = (Map<String, Object>) jsonResponse.get('card');
                result.cardBrand = (String) card.get('brand');
                result.last4 = (String) card.get('last4');
                result.expMonth = (Integer) card.get('exp_month');
                result.expYear = (Integer) card.get('exp_year');
            }
            
            return result;
            
        } else {
            String errorMessage = 'Unknown error';
            String errorCode = 'UNKNOWN';
            
            if (jsonResponse.containsKey('error')) {
                Map<String, Object> error = (Map<String, Object>) jsonResponse.get('error');
                errorCode = (String) error.get('code');
                errorMessage = (String) error.get('message');
            }
            
            return PaymentMethodResponse.failure(errorCode, errorMessage);
        }
    }
    
    /**
     * @description Get charge/payment intent details for transaction sync
     * @param transactionId The Stripe transaction ID (payment intent or charge ID)
     * @return Map<String, Object> The charge details
     */
    public Map<String, Object> getChargeDetails(String transactionId) {
        try {
            String endpoint;
            
            // Determine if this is a PaymentIntent or Charge ID
            if (transactionId.startsWith('pi_')) {
                endpoint = getApiBaseUrl() + '/payment_intents/' + transactionId;
            } else if (transactionId.startsWith('ch_')) {
                endpoint = getApiBaseUrl() + '/charges/' + transactionId;
            } else {
                // Try payment intent first
                endpoint = getApiBaseUrl() + '/payment_intents/' + transactionId;
            }
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint(endpoint);
            request.setMethod('GET');
            setAuthorizationHeader(request);
            request.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                
                // If this is a payment intent, get the latest charge
                if (result.containsKey('latest_charge')) {
                    String chargeId = (String) result.get('latest_charge');
                    if (String.isNotBlank(chargeId)) {
                        // Fetch charge details
                        return getChargeById(chargeId);
                    }
                }
                
                // For direct charge or payment intent without latest_charge
                return result;
            }
            
            return null;
            
        } catch (Exception e) {
            System.debug('Error getting charge details: ' + e.getMessage());
            return null;
        }
    }
    
    /**
     * @description Get charge by ID
     */
    private Map<String, Object> getChargeById(String chargeId) {
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(getApiBaseUrl() + '/charges/' + chargeId);
            request.setMethod('GET');
            setAuthorizationHeader(request);
            request.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            }
            
            return null;
            
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Get payment intent status
     */
    public Map<String, Object> getPaymentIntentStatus(String paymentIntentId) {
        try {
            HttpRequest request = new HttpRequest();
            request.setEndpoint(getApiBaseUrl() + '/payment_intents/' + paymentIntentId);
            request.setMethod('GET');
            setAuthorizationHeader(request);
            request.setTimeout(30000);
            
            Http http = new Http();
            HttpResponse response = http.send(request);
            
            if (response.getStatusCode() == 200) {
                return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            }
            
            return null;
            
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * @description Map Stripe status to our status values
     */
    private String mapStripeStatus(String stripeStatus) {
        Map<String, String> statusMap = new Map<String, String>{
            'succeeded' => 'Approved',
            'processing' => 'Pending',
            'requires_payment_method' => 'Declined',
            'requires_confirmation' => 'Pending',
            'requires_action' => 'Pending',
            'canceled' => 'Voided',
            'requires_capture' => 'Approved'
        };
        
        return statusMap.containsKey(stripeStatus) ? statusMap.get(stripeStatus) : 'Unknown';
    }
}
