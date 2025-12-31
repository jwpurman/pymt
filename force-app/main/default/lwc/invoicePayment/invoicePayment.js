import { LightningElement, api, track, wire } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getActiveGateways from '@salesforce/apex/PaymentService.getActiveGateways';

import INVOICE_ACCOUNT from '@salesforce/schema/Invoice__c.Account__c';
import INVOICE_TOTAL from '@salesforce/schema/Invoice__c.Total_Amount__c';
import INVOICE_BALANCE from '@salesforce/schema/Invoice__c.Balance_Due__c';
import INVOICE_STATUS from '@salesforce/schema/Invoice__c.Status__c';
import INVOICE_GATEWAY from '@salesforce/schema/Invoice__c.Payment_Gateway__c';
import INVOICE_NAME from '@salesforce/schema/Invoice__c.Name';

const INVOICE_FIELDS = [
    INVOICE_ACCOUNT, INVOICE_TOTAL, INVOICE_BALANCE, 
    INVOICE_STATUS, INVOICE_GATEWAY, INVOICE_NAME
];

export default class InvoicePayment extends NavigationMixin(LightningElement) {
    @api recordId; // Invoice ID
    
    @track isLoading = false;
    @track currentStep = 'payment'; // payment, confirmation
    @track gateways = [];
    @track selectedGatewayId;
    @track paymentType = 'full';
    @track partialAmount = 0;
    @track paymentResult;
    
    @wire(getRecord, { recordId: '$recordId', fields: INVOICE_FIELDS })
    invoice;
    
    connectedCallback() {
        this.loadGateways();
    }
    
    async loadGateways() {
        try {
            this.gateways = await getActiveGateways();
        } catch (error) {
            console.error('Error loading gateways:', error);
        }
    }
    
    // Getters for invoice fields
    get accountId() {
        return getFieldValue(this.invoice.data, INVOICE_ACCOUNT);
    }
    
    get invoiceName() {
        return getFieldValue(this.invoice.data, INVOICE_NAME);
    }
    
    get totalAmount() {
        return getFieldValue(this.invoice.data, INVOICE_TOTAL) || 0;
    }
    
    get balanceDue() {
        return getFieldValue(this.invoice.data, INVOICE_BALANCE) || 0;
    }
    
    get invoiceStatus() {
        return getFieldValue(this.invoice.data, INVOICE_STATUS);
    }
    
    get invoiceGatewayId() {
        return getFieldValue(this.invoice.data, INVOICE_GATEWAY);
    }
    
    get gatewayId() {
        return this.selectedGatewayId || this.invoiceGatewayId || 
               (this.gateways.length > 0 ? this.gateways[0].id : null);
    }
    
    get paymentAmount() {
        return this.paymentType === 'full' ? this.balanceDue : this.partialAmount;
    }
    
    get formattedBalanceDue() {
        return this.formatCurrency(this.balanceDue);
    }
    
    get formattedPaymentAmount() {
        return this.formatCurrency(this.paymentAmount);
    }
    
    get invoiceAllocations() {
        return [{
            invoiceId: this.recordId,
            amount: this.paymentAmount,
            isFullPayment: this.paymentType === 'full'
        }];
    }
    
    get isPaymentStep() {
        return this.currentStep === 'payment';
    }
    
    get isConfirmationStep() {
        return this.currentStep === 'confirmation';
    }
    
    get paymentTypeOptions() {
        return [
            { label: 'Full Payment (' + this.formattedBalanceDue + ')', value: 'full' },
            { label: 'Partial Payment', value: 'partial' }
        ];
    }
    
    get showPartialAmount() {
        return this.paymentType === 'partial';
    }
    
    get canSubmit() {
        if (this.balanceDue <= 0) return false;
        if (this.paymentType === 'partial' && this.partialAmount <= 0) return false;
        return true;
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
    
    handlePaymentTypeChange(event) {
        this.paymentType = event.detail.value;
        if (this.paymentType === 'full') {
            this.partialAmount = 0;
        } else {
            this.partialAmount = this.balanceDue;
        }
    }
    
    handlePartialAmountChange(event) {
        this.partialAmount = Math.min(
            parseFloat(event.target.value) || 0,
            this.balanceDue
        );
    }
    
    handleGatewayChange(event) {
        this.selectedGatewayId = event.detail.value;
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
}
