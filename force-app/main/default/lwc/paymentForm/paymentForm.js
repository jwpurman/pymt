import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getGatewayConfig from '@salesforce/apex/PaymentService.getGatewayConfiguration';
import processPayment from '@salesforce/apex/PaymentService.processPayment';
import getPaymentMethods from '@salesforce/apex/PaymentService.getPaymentMethods';

export default class PaymentForm extends LightningElement {
    @api recordId;
    @api accountId;
    @api gatewayId;
    @api amount;
    @api invoiceAllocations = [];
    
    @track isLoading = false;
    @track gatewayConfig;
    @track paymentMethods = [];
    @track selectedPaymentMethodId;
    @track useNewCard = true;
    @track savePaymentMethod = false;
    @track setAsPrimary = false;
    
    // Card details (for display only - actual card data goes to gateway)
    @track cardNumber = '';
    @track detectedCardType = '';
    @track cardValid = false;
    @track expiryValid = false;
    @track cvvValid = false;
    
    // Stripe Elements reference
    stripeElements;
    cardElement;
    stripeInstance;
    
    connectedCallback() {
        this.loadGatewayConfig();
        this.loadPaymentMethods();
    }
    
    async loadGatewayConfig() {
        try {
            this.isLoading = true;
            this.gatewayConfig = await getGatewayConfig({ gatewayId: this.gatewayId });
            await this.initializeGatewayLibrary();
        } catch (error) {
            this.showError('Error loading gateway configuration: ' + error.body?.message);
        } finally {
            this.isLoading = false;
        }
    }
    
    async loadPaymentMethods() {
        if (!this.accountId) return;
        
        try {
            const methods = await getPaymentMethods({ accountId: this.accountId });
            this.paymentMethods = methods.filter(m => !m.isExpired);
            this.useNewCard = this.paymentMethods.length === 0;
        } catch (error) {
            console.error('Error loading payment methods:', error);
        }
    }
    
    async initializeGatewayLibrary() {
        if (!this.gatewayConfig) return;
        
        const gatewayType = this.gatewayConfig.gatewayType;
        
        switch (gatewayType) {
            case 'Stripe':
                await this.initializeStripe();
                break;
            case 'Authorize.Net':
                await this.initializeAuthorizeNet();
                break;
            default:
                console.log('Gateway type not yet supported for client-side tokenization');
        }
    }
    
    async initializeStripe() {
        // Load Stripe.js
        if (!window.Stripe) {
            await this.loadScript('https://js.stripe.com/v3/');
        }
        
        this.stripeInstance = window.Stripe(this.gatewayConfig.publicKey);
        this.stripeElements = this.stripeInstance.elements();
        
        // Create card element
        const style = {
            base: {
                fontSize: '16px',
                color: '#32325d',
                fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
                '::placeholder': {
                    color: '#aab7c4'
                }
            },
            invalid: {
                color: '#fa755a',
                iconColor: '#fa755a'
            }
        };
        
        this.cardElement = this.stripeElements.create('card', { style });
        
        // Mount after render
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            const container = this.template.querySelector('.stripe-card-element');
            if (container) {
                this.cardElement.mount(container);
                
                // Listen for card type changes
                this.cardElement.on('change', (event) => {
                    this.handleStripeCardChange(event);
                });
            }
        }, 100);
    }
    
    async initializeAuthorizeNet() {
        // Load Accept.js
        if (!window.Accept) {
            const scriptUrl = this.gatewayConfig.isTestMode 
                ? 'https://jstest.authorize.net/v1/Accept.js'
                : 'https://js.authorize.net/v1/Accept.js';
            await this.loadScript(scriptUrl);
        }
    }
    
    loadScript(src) {
        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = src;
            script.onload = resolve;
            script.onerror = reject;
            document.head.appendChild(script);
        });
    }
    
    handleStripeCardChange(event) {
        if (event.brand) {
            this.detectedCardType = this.mapStripeBrand(event.brand);
        }
        
        this.cardValid = event.complete;
        
        if (event.error) {
            this.showError(event.error.message);
        }
    }
    
    mapStripeBrand(stripeBrand) {
        const brandMap = {
            'visa': 'Visa',
            'mastercard': 'Mastercard',
            'amex': 'American Express',
            'discover': 'Discover',
            'diners': 'Diners Club',
            'jcb': 'JCB',
            'unionpay': 'UnionPay',
            'unknown': 'Unknown'
        };
        return brandMap[stripeBrand] || 'Unknown';
    }
    
    // Card number input handler for manual detection (when not using Stripe Elements)
    handleCardNumberInput(event) {
        const value = event.target.value.replace(/\s/g, '');
        this.cardNumber = value;
        this.detectedCardType = this.detectCardType(value);
    }
    
    detectCardType(number) {
        const patterns = {
            'Visa': /^4/,
            'Mastercard': /^(5[1-5]|2[2-7])/,
            'American Express': /^3[47]/,
            'Discover': /^(6011|65|64[4-9])/,
            'Diners Club': /^(36|38|30[0-5])/,
            'JCB': /^35/,
            'UnionPay': /^62/
        };
        
        for (const [brand, pattern] of Object.entries(patterns)) {
            if (pattern.test(number)) {
                return brand;
            }
        }
        return '';
    }
    
    handlePaymentMethodChange(event) {
        this.selectedPaymentMethodId = event.detail.value;
        this.useNewCard = !this.selectedPaymentMethodId;
    }
    
    handleUseNewCard() {
        this.useNewCard = true;
        this.selectedPaymentMethodId = null;
    }
    
    handleSavePaymentMethodChange(event) {
        this.savePaymentMethod = event.target.checked;
    }
    
    handleSetAsPrimaryChange(event) {
        this.setAsPrimary = event.target.checked;
    }
    
    get paymentMethodOptions() {
        return this.paymentMethods.map(pm => ({
            label: `${pm.cardBrand} •••• ${pm.lastFour} (Exp: ${pm.expMonth}/${pm.expYear})${pm.isPrimary ? ' - Primary' : ''}`,
            value: pm.id
        }));
    }
    
    get hasPaymentMethods() {
        return this.paymentMethods.length > 0;
    }
    
    get showCardForm() {
        return this.useNewCard;
    }
    
    get isStripe() {
        return this.gatewayConfig?.gatewayType === 'Stripe';
    }
    
    get formattedAmount() {
        if (!this.amount) return '$0.00';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(this.amount);
    }
    
    get canSubmit() {
        if (this.isLoading) return false;
        if (!this.amount || this.amount <= 0) return false;
        
        if (this.useNewCard) {
            return this.cardValid;
        } else {
            return !!this.selectedPaymentMethodId;
        }
    }
    
    get cannotSubmit() {
        return !this.canSubmit;
    }
    
    async handleSubmit() {
        this.isLoading = true;
        
        try {
            let paymentToken;
            
            if (this.useNewCard) {
                // Tokenize the card
                paymentToken = await this.tokenizeCard();
                if (!paymentToken) {
                    return;
                }
            }
            
            // Build payment data
            const paymentData = {
                amount: this.amount,
                currencyCode: 'USD',
                accountId: this.accountId,
                gatewayId: this.gatewayId,
                paymentMethodId: this.useNewCard ? null : this.selectedPaymentMethodId,
                cardToken: this.useNewCard ? paymentToken : null,
                savePaymentMethod: this.savePaymentMethod,
                setAsPrimary: this.setAsPrimary,
                invoiceAllocations: this.invoiceAllocations
            };
            
            const result = await processPayment({ paymentData });
            
            if (result.success) {
                this.showSuccess('Payment processed successfully!');
                this.dispatchEvent(new CustomEvent('paymentsuccess', {
                    detail: {
                        transactionId: result.transactionId,
                        gatewayTransactionId: result.gatewayTransactionId
                    }
                }));
            } else {
                this.showError('Payment failed: ' + result.message);
                this.dispatchEvent(new CustomEvent('paymentfailure', {
                    detail: { message: result.message }
                }));
            }
            
        } catch (error) {
            this.showError('Error processing payment: ' + (error.body?.message || error.message));
        } finally {
            this.isLoading = false;
        }
    }
    
    async tokenizeCard() {
        if (this.isStripe && this.cardElement) {
            const { token, error } = await this.stripeInstance.createToken(this.cardElement);
            
            if (error) {
                this.showError(error.message);
                return null;
            }
            
            return token.id;
        }
        
        // Add other gateway tokenization here
        return null;
    }
    
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
    
    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message,
            variant: 'success'
        }));
    }
    
    showError(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }
}
