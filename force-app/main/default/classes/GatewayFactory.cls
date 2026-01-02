/**
 * @description Factory class for creating payment gateway instances.
 * Uses the factory pattern to instantiate the correct gateway implementation
 * based on the gateway type.
 */
public class GatewayFactory {
    
    // Cache for gateway instances to avoid repeated instantiation
    private static Map<Id, PaymentGateway> gatewayCache = new Map<Id, PaymentGateway>();
    
    /**
     * @description Get a gateway instance by gateway record ID
     * @param gatewayId The Salesforce ID of the Payment Gateway record
     * @return PaymentGateway The gateway instance
     */
    public static PaymentGateway getGateway(Id gatewayId) {
        // Check cache first
        if (gatewayCache.containsKey(gatewayId)) {
            return gatewayCache.get(gatewayId);
        }
        
        // Query the gateway configuration
        pymts__Payment_Gateway__c gatewayConfig = [
            SELECT Id, Name, pymts__Gateway_Type__c, pymts__Active__c,
                   pymts__Environment__c, pymts__Public_Key__c, pymts__Is_Default__c
            FROM pymts__Payment_Gateway__c
            WHERE Id = :gatewayId
            LIMIT 1
        ];
        
        PaymentGateway gateway = createGatewayInstance(gatewayConfig);
        gatewayCache.put(gatewayId, gateway);
        
        return gateway;
    }
    
    /**
     * @description Get a gateway instance from a gateway record
     * @param gatewayConfig The Payment Gateway record
     * @return PaymentGateway The gateway instance
     */
    public static PaymentGateway getGateway(pymts__Payment_Gateway__c gatewayConfig) {
        // Check cache first
        if (gatewayCache.containsKey(gatewayConfig.Id)) {
            return gatewayCache.get(gatewayConfig.Id);
        }
        
        PaymentGateway gateway = createGatewayInstance(gatewayConfig);
        gatewayCache.put(gatewayConfig.Id, gateway);
        
        return gateway;
    }
    
    /**
     * @description Get the default gateway for the org
     * @return PaymentGateway The default gateway instance
     */
    public static PaymentGateway getDefaultGateway() {
        pymts__Payment_Gateway__c defaultGateway = [
            SELECT Id, Name, pymts__Gateway_Type__c, pymts__Active__c,
                   pymts__Environment__c, pymts__Public_Key__c, pymts__Is_Default__c
            FROM pymts__Payment_Gateway__c
            WHERE pymts__Is_Default__c = true AND pymts__Active__c = true
            LIMIT 1
        ];
        
        if (defaultGateway == null) {
            throw new GatewayFactoryException('No default payment gateway configured');
        }
        
        return getGateway(defaultGateway);
    }
    
    /**
     * @description Create a gateway instance based on gateway type
     * @param gatewayConfig The gateway configuration
     * @return PaymentGateway The gateway instance
     */
    private static PaymentGateway createGatewayInstance(pymts__Payment_Gateway__c gatewayConfig) {
        if (!gatewayConfig.pymts__Active__c) {
            throw new GatewayFactoryException('Gateway is not active: ' + gatewayConfig.Name);
        }
        
        String gatewayType = gatewayConfig.pymts__Gateway_Type__c;
        
        switch on gatewayType {
            when 'Stripe' {
                return new StripeGateway(gatewayConfig);
            }
            when 'Authorize.Net' {
                return new AuthorizeNetGateway(gatewayConfig);
            }
            when 'Braintree' {
                return new BraintreeGateway(gatewayConfig);
            }
            when 'PayPal' {
                return new PayPalGateway(gatewayConfig);
            }
            when 'Square' {
                return new SquareGateway(gatewayConfig);
            }
            when 'Placetopay' {
                return new PlacetopayGateway(gatewayConfig);
            }
            when else {
                throw new GatewayFactoryException('Unsupported gateway type: ' + gatewayType);
            }
        }
    }
    
    /**
     * @description Get all active gateways
     * @return List<pymts__Payment_Gateway__c> List of active gateway records
     */
    public static List<pymts__Payment_Gateway__c> getActiveGateways() {
        return [
            SELECT Id, Name, pymts__Gateway_Type__c, pymts__Active__c,
                   pymts__Environment__c, pymts__Public_Key__c, pymts__Is_Default__c
            FROM pymts__Payment_Gateway__c
            WHERE pymts__Active__c = true
            ORDER BY pymts__Is_Default__c DESC, Name ASC
        ];
    }
    
    /**
     * @description Clear the gateway cache (useful for testing)
     */
    public static void clearCache() {
        gatewayCache.clear();
    }
    
    /**
     * @description Check if a gateway type is supported
     * @param gatewayType The gateway type to check
     * @return Boolean True if supported
     */
    public static Boolean isGatewayTypeSupported(String gatewayType) {
        Set<String> supportedTypes = new Set<String>{
            'Stripe', 'Authorize.Net', 'Braintree', 'PayPal', 'Square', 
            'Adyen', 'Worldpay', 'CyberSource', 'Placetopay'
        };
        return supportedTypes.contains(gatewayType);
    }
    
    /**
     * @description Get the client library URL for a gateway
     * @param gatewayType The gateway type
     * @return String The JavaScript library URL
     */
    public static String getClientLibraryUrl(String gatewayType) {
        Map<String, String> libraryUrls = new Map<String, String>{
            'Stripe' => 'https://js.stripe.com/v3/',
            'Authorize.Net' => 'https://js.authorize.net/v1/Accept.js',
            'Braintree' => 'https://js.braintreegateway.com/web/dropin/1.33.0/js/dropin.min.js',
            'PayPal' => 'https://www.paypal.com/sdk/js',
            'Square' => 'https://sandbox.web.squarecdn.com/v1/square.js',
            'Placetopay' => 'https://checkout.placetopay.com/js/checkout.js'
        };
        return libraryUrls.get(gatewayType);
    }
    
    /**
     * @description Custom exception for factory errors
     */
    public class GatewayFactoryException extends Exception {}
}
