import { LightningElement, api, track } from 'lwc';

export default class AchPaymentEntry extends LightningElement {
    @api accountId;
    @api gatewayId;
    @api showAmount = false;
    @api allowSaveMethod = false;
    @api hideCancel = false;
    @api submitLabel = 'Submit Payment';
    
    @track accountType = 'checking';
    @track nameOnAccount = '';
    @track bankName = '';
    @track routingNumber = '';
    @track accountNumber = '';
    @track confirmAccountNumber = '';
    @track amount = 0;
    @track savePaymentMethod = false;
    @track authorized = false;
    @track error;
    @track isProcessing = false;
    
    // Known routing numbers (partial list for validation display)
    routingInfo = {
        '021000021': 'JPMorgan Chase',
        '011401533': 'Bank of America',
        '121000248': 'Wells Fargo',
        '021000089': 'Citibank',
        '071000013': 'BMO Harris',
        '091000019': 'Wells Fargo (Minnesota)',
        '122000247': 'Wells Fargo (California)',
        '026009593': 'Bank of America (New York)'
    };
    
    get accountTypeOptions() {
        return [
            { label: 'Checking', value: 'checking' },
            { label: 'Savings', value: 'savings' },
            { label: 'Business Checking', value: 'businessChecking' }
        ];
    }
    
    get bankInfo() {
        if (this.routingNumber && this.routingNumber.length === 9) {
            const knownBank = this.routingInfo[this.routingNumber];
            if (knownBank) {
                return `Bank: ${knownBank}`;
            }
        }
        return '';
    }
    
    get accountNumberMismatch() {
        return this.accountNumber && 
               this.confirmAccountNumber && 
               this.accountNumber !== this.confirmAccountNumber;
    }
    
    get isSubmitDisabled() {
        return this.isProcessing ||
               !this.authorized ||
               !this.nameOnAccount ||
               !this.routingNumber ||
               !this.accountNumber ||
               !this.confirmAccountNumber ||
               this.accountNumberMismatch ||
               this.routingNumber.length !== 9 ||
               this.accountNumber.length < 4 ||
               (this.showAmount && (!this.amount || this.amount <= 0));
    }
    
    handleAccountTypeChange(event) {
        this.accountType = event.detail.value;
    }
    
    handleNameChange(event) {
        this.nameOnAccount = event.target.value;
    }
    
    handleBankNameChange(event) {
        this.bankName = event.target.value;
    }
    
    handleRoutingChange(event) {
        // Only allow digits
        this.routingNumber = event.target.value.replace(/\D/g, '');
    }
    
    handleAccountNumberChange(event) {
        // Only allow digits
        this.accountNumber = event.target.value.replace(/\D/g, '');
    }
    
    handleConfirmAccountChange(event) {
        this.confirmAccountNumber = event.target.value.replace(/\D/g, '');
    }
    
    handleAmountChange(event) {
        this.amount = parseFloat(event.target.value) || 0;
    }
    
    handleSaveMethodChange(event) {
        this.savePaymentMethod = event.target.checked;
    }
    
    handleAuthorizationChange(event) {
        this.authorized = event.target.checked;
    }
    
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
    
    handleSubmit() {
        // Validate all inputs
        const allValid = [...this.template.querySelectorAll('lightning-input')]
            .reduce((validSoFar, inputCmp) => {
                inputCmp.reportValidity();
                return validSoFar && inputCmp.checkValidity();
            }, true);
        
        if (!allValid) {
            return;
        }
        
        if (this.accountNumberMismatch) {
            this.error = 'Account numbers do not match';
            return;
        }
        
        if (!this.authorized) {
            this.error = 'Please authorize the ACH debit';
            return;
        }
        
        this.error = null;
        this.isProcessing = true;
        
        // Dispatch event with ACH details
        const achDetails = {
            accountType: this.accountType,
            nameOnAccount: this.nameOnAccount,
            bankName: this.bankName,
            routingNumber: this.routingNumber,
            accountNumber: this.accountNumber,
            echeckType: this.accountType === 'businessChecking' ? 'CCD' : 'WEB',
            savePaymentMethod: this.savePaymentMethod,
            amount: this.amount
        };
        
        this.dispatchEvent(new CustomEvent('submit', {
            detail: achDetails
        }));
    }
    
    // Public methods for parent component to call
    @api
    setProcessing(isProcessing) {
        this.isProcessing = isProcessing;
    }
    
    @api
    setError(errorMessage) {
        this.error = errorMessage;
        this.isProcessing = false;
    }
    
    @api
    reset() {
        this.accountType = 'checking';
        this.nameOnAccount = '';
        this.bankName = '';
        this.routingNumber = '';
        this.accountNumber = '';
        this.confirmAccountNumber = '';
        this.amount = 0;
        this.savePaymentMethod = false;
        this.authorized = false;
        this.error = null;
        this.isProcessing = false;
    }
    
    @api
    getAchDetails() {
        return {
            accountType: this.accountType,
            nameOnAccount: this.nameOnAccount,
            bankName: this.bankName,
            routingNumber: this.routingNumber,
            accountNumber: this.accountNumber,
            echeckType: this.accountType === 'businessChecking' ? 'CCD' : 'WEB'
        };
    }
    
    @api
    validate() {
        const allValid = [...this.template.querySelectorAll('lightning-input')]
            .reduce((validSoFar, inputCmp) => {
                inputCmp.reportValidity();
                return validSoFar && inputCmp.checkValidity();
            }, true);
        
        return allValid && !this.accountNumberMismatch && this.authorized;
    }
}
