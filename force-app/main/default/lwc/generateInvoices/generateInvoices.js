import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

import getOrderDetails from '@salesforce/apex/InvoiceService.getOrderDetails';
import generateInvoicesFromOrder from '@salesforce/apex/InvoiceService.generateInvoicesFromOrder';
import getActiveGateways from '@salesforce/apex/PaymentService.getActiveGateways';
import previewInvoices from '@salesforce/apex/InvoiceService.previewInvoices';

export default class GenerateInvoices extends NavigationMixin(LightningElement) {
    @api recordId;
    
    @track orderData;
    @track gatewayOptions = [];
    @track invoicePreview;
    @track generatedInvoices;
    @track error;
    
    selectedGateway;
    enableAutoPay = true;
    paymentTerms = 30;
    
    isLoading = true;
    isGenerating = false;
    
    productColumns = [
        { label: 'Product', fieldName: 'productName', type: 'text' },
        { label: 'Quantity', fieldName: 'Quantity', type: 'number' },
        { 
            label: 'Unit Price', 
            fieldName: 'UnitPrice', 
            type: 'currency',
            typeAttributes: { currencyCode: 'USD' }
        },
        { 
            label: 'Total', 
            fieldName: 'TotalPrice', 
            type: 'currency',
            typeAttributes: { currencyCode: 'USD' }
        },
        { label: 'Recurring', fieldName: 'isRecurring', type: 'boolean' }
    ];
    
    invoiceColumns = [
        { 
            label: 'Invoice', 
            fieldName: 'invoiceUrl', 
            type: 'url',
            typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' }
        },
        { 
            label: 'Amount', 
            fieldName: 'pymtTest__Total_Amount__c', 
            type: 'currency',
            typeAttributes: { currencyCode: 'USD' }
        },
        { label: 'Due Date', fieldName: 'pymtTest__Due_Date__c', type: 'date' },
        { label: 'Status', fieldName: 'pymtTest__Status__c', type: 'text' }
    ];
    
    connectedCallback() {
        this.loadData();
    }
    
    async loadData() {
        this.isLoading = true;
        this.error = null;
        
        try {
            // Load order details and gateways in parallel
            const [orderResult, gatewaysResult] = await Promise.all([
                getOrderDetails({ orderId: this.recordId }),
                getActiveGateways()
            ]);
            
            // Process order data
            this.orderData = orderResult;
            
            // Add derived fields to order items
            if (this.orderData.OrderItems) {
                this.orderData.OrderItems = this.orderData.OrderItems.map(item => ({
                    ...item,
                    productName: item.Product2?.Name || 'Unknown Product',
                    isRecurring: item.Product2?.pymtTest__Is_Recurring__c || false
                }));
            }
            
            // Process gateways
            this.gatewayOptions = gatewaysResult.map(gw => ({
                label: gw.Name,
                value: gw.Id
            }));
            
            // Set default gateway
            const defaultGateway = gatewaysResult.find(gw => gw.pymtTest__Is_Default__c);
            if (defaultGateway) {
                this.selectedGateway = defaultGateway.Id;
            } else if (gatewaysResult.length > 0) {
                this.selectedGateway = gatewaysResult[0].Id;
            }
            
            // Generate invoice preview
            await this.generatePreview();
            
        } catch (error) {
            this.error = this.extractErrorMessage(error);
            console.error('Error loading data:', error);
        } finally {
            this.isLoading = false;
        }
    }
    
    async generatePreview() {
        try {
            const preview = await previewInvoices({ 
                orderId: this.recordId,
                paymentTermsDays: this.paymentTerms
            });
            this.invoicePreview = preview;
        } catch (error) {
            console.error('Error generating preview:', error);
        }
    }
    
    get hasProducts() {
        return this.orderData?.OrderItems?.length > 0;
    }
    
    get formattedStartDate() {
        if (!this.orderData?.EffectiveDate) return '';
        return new Date(this.orderData.EffectiveDate).toLocaleDateString();
    }
    
    get formattedEndDate() {
        if (!this.orderData?.EndDate) return '';
        return new Date(this.orderData.EndDate).toLocaleDateString();
    }
    
    handleGatewayChange(event) {
        this.selectedGateway = event.detail.value;
    }
    
    handleAutoPayChange(event) {
        this.enableAutoPay = event.target.checked;
    }
    
    handleTermsChange(event) {
        this.paymentTerms = parseInt(event.target.value, 10) || 30;
        // Regenerate preview when terms change
        this.generatePreview();
    }
    
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    async handleGenerate() {
        this.isGenerating = true;
        this.error = null;
        
        try {
            const invoiceIds = await generateInvoicesFromOrder({
                orderId: this.recordId,
                gatewayId: this.selectedGateway,
                enableAutoPay: this.enableAutoPay,
                paymentTermsDays: this.paymentTerms
            });
            
            // Build invoice list with URLs
            this.generatedInvoices = invoiceIds.map((id, index) => ({
                Id: id,
                Name: `INV-${String(index + 1).padStart(5, '0')}`,
                invoiceUrl: `/lightning/r/pymtTest__Invoice__c/${id}/view`,
                pymtTest__Total_Amount__c: this.invoicePreview?.invoices[index]?.amount || 0,
                pymtTest__Due_Date__c: this.invoicePreview?.invoices[index]?.date,
                pymtTest__Status__c: this.enableAutoPay ? 'Scheduled' : 'Pending'
            }));
            
            this.showToast('Success', `${invoiceIds.length} invoice(s) generated successfully`, 'success');
            
        } catch (error) {
            this.error = this.extractErrorMessage(error);
            this.showToast('Error', this.error, 'error');
        } finally {
            this.isGenerating = false;
        }
    }
    
    handleViewInvoices() {
        // Navigate to related list
        this[NavigationMixin.Navigate]({
            type: 'standard__recordRelationshipPage',
            attributes: {
                recordId: this.orderData.AccountId,
                objectApiName: 'Account',
                relationshipApiName: 'pymtTest__Invoices__r',
                actionName: 'view'
            }
        });
        
        this.dispatchEvent(new CloseActionScreenEvent());
    }
    
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }
    
    extractErrorMessage(error) {
        if (typeof error === 'string') return error;
        if (error.body?.message) return error.body.message;
        if (error.message) return error.message;
        return 'An unexpected error occurred';
    }
}
