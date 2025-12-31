/**
 * @description Test class for GatewayFactory
 */
@isTest
private class GatewayFactoryTest {
    
    @TestSetup
    static void setupTestData() {
        List<pymtTest__Payment_Gateway__c> gateways = new List<pymtTest__Payment_Gateway__c>();
        
        gateways.add(new pymtTest__Payment_Gateway__c(
            Name = 'Stripe Gateway',
            pymtTest__Gateway_Type__c = 'Stripe',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = true,
            pymtTest__Environment__c = 'Test'
        ));
        
        gateways.add(new pymtTest__Payment_Gateway__c(
            Name = 'AuthNet Gateway',
            pymtTest__Gateway_Type__c = 'Authorize.Net',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = false,
            pymtTest__Environment__c = 'Test'
        ));
        
        gateways.add(new pymtTest__Payment_Gateway__c(
            Name = 'Braintree Gateway',
            pymtTest__Gateway_Type__c = 'Braintree',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = false,
            pymtTest__Environment__c = 'Test'
        ));
        
        gateways.add(new pymtTest__Payment_Gateway__c(
            Name = 'PayPal Gateway',
            pymtTest__Gateway_Type__c = 'PayPal',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = false,
            pymtTest__Environment__c = 'Test'
        ));
        
        gateways.add(new pymtTest__Payment_Gateway__c(
            Name = 'Square Gateway',
            pymtTest__Gateway_Type__c = 'Square',
            pymtTest__Active__c = true,
            pymtTest__Is_Default__c = false,
            pymtTest__Environment__c = 'Test'
        ));
        
        insert gateways;
    }
    
    @isTest
    static void testCreateStripeGateway() {
        pymtTest__Payment_Gateway__c gateway = [
            SELECT Id FROM pymtTest__Payment_Gateway__c 
            WHERE pymtTest__Gateway_Type__c = 'Stripe'
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
        pymtTest__Payment_Gateway__c gateway = [
            SELECT Id FROM pymtTest__Payment_Gateway__c 
            WHERE pymtTest__Gateway_Type__c = 'Authorize.Net'
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
        pymtTest__Payment_Gateway__c gateway = [
            SELECT Id FROM pymtTest__Payment_Gateway__c 
            WHERE pymtTest__Gateway_Type__c = 'Braintree'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof BraintreeGateway, 'Should be BraintreeGateway instance');
    }
    
    @isTest
    static void testCreatePayPalGateway() {
        pymtTest__Payment_Gateway__c gateway = [
            SELECT Id FROM pymtTest__Payment_Gateway__c 
            WHERE pymtTest__Gateway_Type__c = 'PayPal'
        ];
        
        Test.startTest();
        PaymentGateway pg = GatewayFactory.getGateway(gateway.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, pg, 'Gateway should not be null');
        System.assert(pg instanceof PayPalGateway, 'Should be PayPalGateway instance');
    }
    
    @isTest
    static void testCreateSquareGateway() {
        pymtTest__Payment_Gateway__c gateway = [
            SELECT Id FROM pymtTest__Payment_Gateway__c 
            WHERE pymtTest__Gateway_Type__c = 'Square'
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
        List<pymtTest__Payment_Gateway__c> gateways = [SELECT Id FROM pymtTest__Payment_Gateway__c];
        for (pymtTest__Payment_Gateway__c gw : gateways) {
            gw.pymtTest__Is_Default__c = false;
            gw.pymtTest__Active__c = false;
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
