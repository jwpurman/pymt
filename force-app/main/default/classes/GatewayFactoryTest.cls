/**
 * @description Test class for GatewayFactory
 */
@isTest
private class GatewayFactoryTest {
    
    @TestSetup
    static void setupTestData() {
        List<pymts__Payment_Gateway__c> gateways = new List<pymts__Payment_Gateway__c>();
        
        gateways.add(new pymts__Payment_Gateway__c(
            Name = 'Stripe Gateway',
            pymts__Gateway_Type__c = 'Stripe',
            pymts__Active__c = true,
            pymts__Is_Default__c = true,
            pymts__Environment__c = 'Test'
        ));
        
        gateways.add(new pymts__Payment_Gateway__c(
            Name = 'AuthNet Gateway',
            pymts__Gateway_Type__c = 'Authorize.Net',
            pymts__Active__c = true,
            pymts__Is_Default__c = false,
            pymts__Environment__c = 'Test'
        ));
        
        gateways.add(new pymts__Payment_Gateway__c(
            Name = 'Braintree Gateway',
            pymts__Gateway_Type__c = 'Braintree',
            pymts__Active__c = true,
            pymts__Is_Default__c = false,
            pymts__Environment__c = 'Test'
        ));
        
        gateways.add(new pymts__Payment_Gateway__c(
            Name = 'PayPal Gateway',
            pymts__Gateway_Type__c = 'PayPal',
            pymts__Active__c = true,
            pymts__Is_Default__c = false,
            pymts__Environment__c = 'Test'
        ));
        
        gateways.add(new pymts__Payment_Gateway__c(
            Name = 'Square Gateway',
            pymts__Gateway_Type__c = 'Square',
            pymts__Active__c = true,
            pymts__Is_Default__c = false,
            pymts__Environment__c = 'Test'
        ));
        
        insert gateways;
    }
    
    @isTest
    static void testCreateStripeGateway() {
        pymts__Payment_Gateway__c gateway = [
            SELECT Id FROM pymts__Payment_Gateway__c 
            WHERE pymts__Gateway_Type__c = 'Stripe'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof StripeGateway, 'Should be StripeGateway instance');
        System.assertEquals('Stripe', pg.getGatewayType(), 'Type should be Stripe');
    }
    
    @isTest
    static void testCreateAuthorizeNetGateway() {
        pymts__Payment_Gateway__c gateway = [
            SELECT Id FROM pymts__Payment_Gateway__c 
            WHERE pymts__Gateway_Type__c = 'Authorize.Net'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof AuthorizeNetGateway, 'Should be AuthorizeNetGateway instance');
        System.assertEquals('Authorize.Net', pg.getGatewayType(), 'Type should be Authorize.Net');
    }
    
    @isTest
    static void testCreateBraintreeGateway() {
        pymts__Payment_Gateway__c gateway = [
            SELECT Id FROM pymts__Payment_Gateway__c 
            WHERE pymts__Gateway_Type__c = 'Braintree'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof BraintreeGateway, 'Should be BraintreeGateway instance');
    }
    
    @isTest
    static void testCreatePayPalGateway() {
        pymts__Payment_Gateway__c gateway = [
            SELECT Id FROM pymts__Payment_Gateway__c 
            WHERE pymts__Gateway_Type__c = 'PayPal'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof PayPalGateway, 'Should be PayPalGateway instance');
    }
    
    @isTest
    static void testCreateSquareGateway() {
        pymts__Payment_Gateway__c gateway = [
            SELECT Id FROM pymts__Payment_Gateway__c 
            WHERE pymts__Gateway_Type__c = 'Square'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof SquareGateway, 'Should be SquareGateway instance');
    }
    
    @isTest
    static void testGetDefaultGateway() {
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getDefaultGateway();
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Default gateway should not be null');
        System.assertEquals('Stripe', pg.getGatewayType(), 'Default should be Stripe');
    }
    
    @isTest
    static void testInvalidGatewayId() {
        Test.startTest();
        try {
            PaymentGateway pg = GatewayFactory.getGateway((Id) '001000000000000AAA');
            System.assert(false, 'Should have thrown exception');
        } catch (GatewayFactory.GatewayFactoryException e) {
            System.assert(e.getMessage() != null);
        }
        Test.stopTest();
    }
    
    @isTest
    static void testNoDefaultGateway() {
        // Deactivate all gateways
        List<pymts__Payment_Gateway__c> gateways = [SELECT Id FROM pymts__Payment_Gateway__c];
        for (pymts__Payment_Gateway__c gw : gateways) {
            gw.pymts__Is_Default__c = false;
            gw.pymts__Active__c = false;
        }
        update gateways;
        
        Test.startTest();
        try {
            PaymentGateway pg = GatewayFactory.getDefaultGateway();
            System.assert(false, 'Should have thrown exception');
        } catch (GatewayFactory.GatewayFactoryException e) {
            System.assert(e.getMessage().contains('No default'), 'Should indicate no default');
        }
        Test.stopTest();
    }
}
