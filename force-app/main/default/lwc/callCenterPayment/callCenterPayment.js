import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchAccounts from '@salesforce/apex/CallCenterService.searchAccounts';
import createQuickAccount from '@salesforce/apex/CallCenterService.createQuickAccount';
import searchProducts from '@salesforce/apex/CallCenterService.searchProducts';
import getPaymentMethods from '@salesforce/apex/CallCenterService.getPaymentMethods';
import processCallCenterPayment from '@salesforce/apex/CallCenterService.processCallCenterPayment';

export default class CallCenterPayment extends LightningElement {
    // Account selection
    @track accountSearchTerm = '';
    @track accountResults = [];
    @track selectedAccount = null;
    @track showAccountSearch = true;
    @track showNewAccountModal = false;
    @track newAccountName = '';
    @track newAccountPhone = '';
    @track newAccountEmail = '';
    
    // Product search and cart
    @track productSearchTerm = '';
    @track productResults = [];
    @track cartItems = [];
    
    // Payment
    @track paymentMethods = [];
    @track selectedPaymentMethodId = '';
    @track paymentType = 'Card';
    @track showNewPaymentForm = false;
    @track savePaymentMethod = false;
    @track sourceDescription = '';
    
    // New card fields
    @track cardNumber = '';
    @track expirationMonth = '';
    @track expirationYear = '';
    @track cvv = '';
    @track billingZip = '';
    
    // New ACH fields
    @track routingNumber = '';
    @track accountNumber = '';
    @track accountType = 'Checking';
    
    // UI state
    @track isLoading = false;
    @track isSearchingAccounts = false;
    @track isSearchingProducts = false;
    
    accountTypeOptions = [
        { label: 'Checking', value: 'Checking' },
        { label: 'Savings', value: 'Savings' }
    ];
    
    paymentTypeOptions = [
        { label: 'Credit/Debit Card', value: 'Card' },
        { label: 'Bank Account (ACH)', value: 'ACH' }
    ];
    
    get cartTotal() {
        return this.cartItems.reduce((total, item) => total + (item.quantity * item.unitPrice), 0);
    }
    
    get formattedCartTotal() {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(this.cartTotal);
    }
    
    get hasCartItems() {
        return this.cartItems.length > 0;
    }
    
    get canProcessPayment() {
        return this.selectedAccount && 
               this.hasCartItems && 
               (this.selectedPaymentMethodId || this.showNewPaymentForm);
    }
    
    get cannotProcessPayment() {
        return !this.canProcessPayment;
    }
    
    get noAccountSelected() {
        return !this.selectedAccount;
    }
    
    get hasPaymentMethods() {
        return this.paymentMethods.length > 0;
    }
    
    get paymentMethodOptions() {
        return this.paymentMethods.map(pm => ({
            label: `${pm.pymts__Type__c} ending in ${pm.pymts__Last_Four__c}${pm.pymts__Is_Primary__c ? ' (Primary)' : ''}`,
            value: pm.Id
        }));
    }
    
    get isCardPayment() {
        return this.paymentType === 'Card';
    }
    
    get isACHPayment() {
        return this.paymentType === 'ACH';
    }
    
    // Account Search
    handleAccountSearch(event) {
        this.accountSearchTerm = event.target.value;
        if (this.accountSearchTerm.length >= 3) {
            this.searchAccountsDebounced();
        } else {
            this.accountResults = [];
        }
    }
    
    searchAccountsDebounced() {
        clearTimeout(this.accountSearchTimeout);
        this.accountSearchTimeout = setTimeout(() => {
            this.performAccountSearch();
        }, 300);
    }
    
    async performAccountSearch() {
        this.isSearchingAccounts = true;
        try {
            this.accountResults = await searchAccounts({ searchTerm: this.accountSearchTerm });
        } catch (error) {
            this.showError('Error searching accounts', error.body?.message || error.message);
        } finally {
            this.isSearchingAccounts = false;
        }
    }
    
    selectAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        this.selectedAccount = this.accountResults.find(acc => acc.Id === accountId);
        this.showAccountSearch = false;
        this.accountResults = [];
        this.loadPaymentMethods();
    }
    
    clearAccount() {
        this.selectedAccount = null;
        this.showAccountSearch = true;
        this.accountSearchTerm = '';
        this.paymentMethods = [];
        this.selectedPaymentMethodId = '';
    }
    
    // Quick Account Creation
    openNewAccountModal() {
        this.showNewAccountModal = true;
    }
    
    closeNewAccountModal() {
        this.showNewAccountModal = false;
        this.newAccountName = '';
        this.newAccountPhone = '';
        this.newAccountEmail = '';
    }
    
    handleNewAccountField(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;
    }
    
    async createAccount() {
        if (!this.newAccountName) {
            this.showError('Validation Error', 'Account name is required');
            return;
        }
        
        this.isLoading = true;
        try {
            const newAccount = await createQuickAccount({
                accountName: this.newAccountName,
                phone: this.newAccountPhone,
                email: this.newAccountEmail
            });
            this.selectedAccount = newAccount;
            this.showAccountSearch = false;
            this.closeNewAccountModal();
            this.showSuccess('Account Created', `${newAccount.Name} has been created`);
        } catch (error) {
            this.showError('Error creating account', error.body?.message || error.message);
        } finally {
            this.isLoading = false;
        }
    }
    
    // Product Search
    handleProductSearch(event) {
        this.productSearchTerm = event.target.value;
        if (this.productSearchTerm.length >= 2) {
            this.searchProductsDebounced();
        } else {
            this.productResults = [];
        }
    }
    
    searchProductsDebounced() {
        clearTimeout(this.productSearchTimeout);
        this.productSearchTimeout = setTimeout(() => {
            this.performProductSearch();
        }, 300);
    }
    
    async performProductSearch() {
        this.isSearchingProducts = true;
        try {
            this.productResults = await searchProducts({ searchTerm: this.productSearchTerm });
        } catch (error) {
            this.showError('Error searching products', error.body?.message || error.message);
        } finally {
            this.isSearchingProducts = false;
        }
    }
    
    addToCart(event) {
        const productId = event.currentTarget.dataset.id;
        const product = this.productResults.find(p => p.id === productId);
        
        // Check if already in cart
        const existingItem = this.cartItems.find(item => item.productId === productId);
        if (existingItem) {
            existingItem.quantity += 1;
            existingItem.totalPrice = existingItem.quantity * existingItem.unitPrice;
            this.cartItems = [...this.cartItems];
        } else {
            this.cartItems = [...this.cartItems, {
                productId: product.id,
                productName: product.name,
                productCode: product.productCode,
                quantity: 1,
                unitPrice: product.unitPrice,
                totalPrice: product.unitPrice
            }];
        }
        
        this.productSearchTerm = '';
        this.productResults = [];
    }
    
    updateQuantity(event) {
        const productId = event.currentTarget.dataset.id;
        const newQuantity = parseInt(event.target.value, 10);
        
        if (newQuantity <= 0) {
            this.removeFromCart({ currentTarget: { dataset: { id: productId } } });
            return;
        }
        
        const item = this.cartItems.find(i => i.productId === productId);
        if (item) {
            item.quantity = newQuantity;
            item.totalPrice = item.quantity * item.unitPrice;
            this.cartItems = [...this.cartItems];
        }
    }
    
    removeFromCart(event) {
        const productId = event.currentTarget.dataset.id;
        this.cartItems = this.cartItems.filter(item => item.productId !== productId);
    }
    
    clearCart() {
        if (confirm('Are you sure you want to clear the cart?')) {
            this.cartItems = [];
        }
    }
    
    // Payment Methods
    async loadPaymentMethods() {
        if (!this.selectedAccount) return;
        
        try {
            this.paymentMethods = await getPaymentMethods({ accountId: this.selectedAccount.Id });
            if (this.paymentMethods.length > 0) {
                // Auto-select primary or first method
                const primary = this.paymentMethods.find(pm => pm.pymts__Is_Primary__c);
                this.selectedPaymentMethodId = primary ? primary.Id : this.paymentMethods[0].Id;
            }
        } catch (error) {
            this.showError('Error loading payment methods', error.body?.message || error.message);
        }
    }
    
    handlePaymentMethodChange(event) {
        this.selectedPaymentMethodId = event.detail.value;
        this.showNewPaymentForm = false;
    }
    
    showNewPayment() {
        this.showNewPaymentForm = true;
        this.selectedPaymentMethodId = '';
    }
    
    handlePaymentTypeChange(event) {
        this.paymentType = event.detail.value;
    }
    
    handlePaymentField(event) {
        const field = event.target.dataset.field;
        this[field] = event.target.value;
    }
    
    handleSavePaymentMethodChange(event) {
        this.savePaymentMethod = event.target.checked;
    }
    
    handleSourceDescriptionChange(event) {
        this.sourceDescription = event.target.value;
    }
    
    // Process Payment
    async processPayment() {
        if (!this.validatePayment()) return;
        
        this.isLoading = true;
        
        try {
            // In production, tokenize card data client-side first
            // For this example, we'll simulate tokenization
            const paymentToken = this.showNewPaymentForm ? 'tok_simulated_' + Date.now() : null;
            
            const request = {
                accountId: this.selectedAccount.Id,
                cartItems: this.cartItems,
                paymentMethodId: this.selectedPaymentMethodId || null,
                paymentToken: paymentToken,
                paymentType: this.paymentType,
                savePaymentMethod: this.savePaymentMethod,
                sourceDescription: this.sourceDescription,
                cardLastFour: this.cardNumber ? this.cardNumber.slice(-4) : null,
                cardType: this.detectCardType(this.cardNumber),
                expirationMonth: this.expirationMonth,
                expirationYear: this.expirationYear,
                accountLastFour: this.accountNumber ? this.accountNumber.slice(-4) : null,
                accountType: this.accountType
            };
            
            const result = await processCallCenterPayment({ request: request });
            
            if (result.success) {
                this.showSuccess('Payment Successful', 
                    `Transaction ${result.transactionNumber} for ${this.formatCurrency(result.amount)} has been processed`);
                this.resetForm();
            } else {
                this.showError('Payment Failed', result.errorMessage);
            }
        } catch (error) {
            this.showError('Error processing payment', error.body?.message || error.message);
        } finally {
            this.isLoading = false;
        }
    }
    
    validatePayment() {
        if (!this.selectedAccount) {
            this.showError('Validation Error', 'Please select a customer account');
            return false;
        }
        if (!this.hasCartItems) {
            this.showError('Validation Error', 'Cart cannot be empty');
            return false;
        }
        if (!this.selectedPaymentMethodId && !this.showNewPaymentForm) {
            this.showError('Validation Error', 'Please select or enter a payment method');
            return false;
        }
        if (this.showNewPaymentForm) {
            if (this.isCardPayment) {
                if (!this.cardNumber || !this.expirationMonth || !this.expirationYear || !this.cvv) {
                    this.showError('Validation Error', 'Please fill in all card fields');
                    return false;
                }
            } else {
                if (!this.routingNumber || !this.accountNumber) {
                    this.showError('Validation Error', 'Please fill in all bank account fields');
                    return false;
                }
            }
        }
        return true;
    }
    
    detectCardType(cardNumber) {
        if (!cardNumber) return null;
        const num = cardNumber.replace(/\s/g, '');
        if (/^4/.test(num)) return 'Visa';
        if (/^5[1-5]/.test(num)) return 'Mastercard';
        if (/^3[47]/.test(num)) return 'Amex';
        if (/^6(?:011|5)/.test(num)) return 'Discover';
        return 'Unknown';
    }
    
    formatCurrency(amount) {
        return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
    }
    
    resetForm() {
        this.selectedAccount = null;
        this.showAccountSearch = true;
        this.accountSearchTerm = '';
        this.cartItems = [];
        this.paymentMethods = [];
        this.selectedPaymentMethodId = '';
        this.showNewPaymentForm = false;
        this.sourceDescription = '';
        this.cardNumber = '';
        this.expirationMonth = '';
        this.expirationYear = '';
        this.cvv = '';
        this.billingZip = '';
        this.routingNumber = '';
        this.accountNumber = '';
    }
    
    showSuccess(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success'
        }));
    }
    
    showError(title, message) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error'
        }));
    }
}
