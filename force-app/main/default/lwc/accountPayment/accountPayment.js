import { LightningElement, api, track } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import getActiveGateways from '@salesforce/apex/PaymentService.getActiveGateways';
import getAccountCredits from '@salesforce/apex/PaymentService.getAccountCredits';

export default class AccountPayment extends NavigationMixin(LightningElement) {
    @api recordId; // Account ID from quick action
    
    @track currentStep = 'select'; // select, payment, confirmation
    @track isLoading = false;
    @track gateways = [];
    @track selectedGatewayId;
    @track accountCredits = [];
    @track applyCredits = false;
    @track creditAmountToApply = 0;
    
    // From invoice selector
    @track invoiceAllocations = [];
    @track totalAmount = 0;
    @track invoiceCount = 0;
    
    // Payment result
    @track paymentResult;
    
    connectedCallback() {
        this.loadGateways();
        this.loadAccountCredits();
    }
    
    async loadGateways() {
        try {
            this.gateways = await getActiveGateways();
            if (this.gateways.length > 0) {
                // Select default gateway
                const defaultGateway = this.gateways.find(g => g.isDefault) || this.gateways[0];
                this.selectedGatewayId = defaultGateway.id;
            }
        } catch (error) {
            this.showError('Error loading payment gateways');
        }
    }
    
    async loadAccountCredits() {
        try {
            this.accountCredits = await getAccountCredits({ accountId: this.recordId });
        } catch (error) {
            console.error('Error loading account credits:', error);
        }
    }
    
    handleInvoiceSelectionChange(event) {
        this.invoiceAllocations = event.detail.allocations;
        this.totalAmount = event.detail.totalAmount;
        this.invoiceCount = event.detail.invoiceCount;
    }
    
    handleGatewayChange(event) {
        this.selectedGatewayId = event.detail.value;
    }
    
    handleApplyCreditsChange(event) {
        this.applyCredits = event.target.checked;
        if (!this.applyCredits) {
            this.creditAmountToApply = 0;
        } else {
            // Default to applying full available credit or total amount, whichever is less
            this.creditAmountToApply = Math.min(this.totalAvailableCredit, this.totalAmount);
        }
    }
    
    handleCreditAmountChange(event) {
        this.creditAmountToApply = Math.min(
            parseFloat(event.target.value) || 0,
            this.totalAvailableCredit,
            this.totalAmount
        );
    }
    
    handleNext() {
        if (this.currentStep === 'select') {
            if (this.invoiceCount === 0) {
                this.showError('Please select at least one invoice');
                return;
            }
            this.currentStep = 'payment';
        }
    }
    
    handleBack() {
        if (this.currentStep === 'payment') {
            this.currentStep = 'select';
        }
    }
    
    handlePaymentSuccess(event) {
        this.paymentResult = {
            success: true,
            transactionId: event.detail.transactionId,
            gatewayTransactionId: event.detail.gatewayTransactionId
        };
        this.currentStep = 'confirmation';
    }
    
    handlePaymentFailure(event) {
        this.showError(event.detail.message);
    }
    
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    handleDone() {
        // Navigate to the transaction record
        if (this.paymentResult?.transactionId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.paymentResult.transactionId,
                    objectApiName: 'pymtTest__Transaction__c',
                    actionName: 'view'
                }
            });
        }
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    handleViewInvoices() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    // Getters
    get isSelectStep() {
        return this.currentStep === 'select';
    }
    
    get isPaymentStep() {
        return this.currentStep === 'payment';
    }
    
    get isConfirmationStep() {
        return this.currentStep === 'confirmation';
    }
    
    get gatewayOptions() {
        return this.gateways.map(g => ({
            label: `${g.name} (${g.gatewayType})`,
            value: g.id
        }));
    }
    
    get hasMultipleGateways() {
        return this.gateways.length > 1;
    }
    
    get formattedTotalAmount() {
        return this.formatCurrency(this.totalAmount);
    }
    
    get amountAfterCredits() {
        return Math.max(0, this.totalAmount - this.creditAmountToApply);
    }
    
    get formattedAmountAfterCredits() {
        return this.formatCurrency(this.amountAfterCredits);
    }
    
    get hasAccountCredits() {
        return this.accountCredits.length > 0 && this.totalAvailableCredit > 0;
    }
    
    get totalAvailableCredit() {
        return this.accountCredits.reduce((sum, c) => sum + c.remainingBalance, 0);
    }
    
    get formattedAvailableCredit() {
        return this.formatCurrency(this.totalAvailableCredit);
    }
    
    get formattedCreditAmount() {
        return this.formatCurrency(this.creditAmountToApply);
    }
    
    get canProceedToPayment() {
        return this.invoiceCount > 0 && this.selectedGatewayId;
    }
    
    get cannotProceedToPayment() {
        return !this.canProceedToPayment;
    }
    
    get paymentAmount() {
        return this.amountAfterCredits;
    }
    
    get allocationsForPayment() {
        // Adjust allocations if credits are applied
        if (!this.applyCredits || this.creditAmountToApply <= 0) {
            return this.invoiceAllocations;
        }
        
        // Distribute credit across invoices proportionally
        let remainingCredit = this.creditAmountToApply;
        return this.invoiceAllocations.map(alloc => {
            const creditForInvoice = Math.min(remainingCredit, alloc.amount);
            remainingCredit -= creditForInvoice;
            return {
                ...alloc,
                amount: alloc.amount - creditForInvoice
            };
        }).filter(alloc => alloc.amount > 0);
    }
    
    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value || 0);
    }
    
    showError(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }
    
    showSuccess(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Success',
            message,
            variant: 'success'
        }));
    }
}
