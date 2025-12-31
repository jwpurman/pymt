import { LightningElement, api, track } from 'lwc';
import getOpenInvoices from '@salesforce/apex/PaymentService.getOpenInvoices';

export default class InvoiceSelector extends LightningElement {
    @api accountId;
    
    @track invoices = [];
    @track selectedInvoices = new Map();
    @track isLoading = false;
    @track error;
    
    connectedCallback() {
        this.loadInvoices();
    }
    
    async loadInvoices() {
        if (!this.accountId) return;
        
        this.isLoading = true;
        this.error = null;
        
        try {
            const data = await getOpenInvoices({ accountId: this.accountId });
            this.invoices = data.map(inv => ({
                ...inv,
                selected: false,
                paymentType: 'full',
                paymentAmount: inv.balanceDue,
                formattedTotalAmount: this.formatCurrency(inv.totalAmount),
                formattedAmountPaid: this.formatCurrency(inv.amountPaid),
                formattedBalanceDue: this.formatCurrency(inv.balanceDue),
                formattedDueDate: this.formatDate(inv.dueDate),
                isOverdue: new Date(inv.dueDate) < new Date()
            }));
        } catch (err) {
            this.error = err.body?.message || 'Error loading invoices';
        } finally {
            this.isLoading = false;
        }
    }
    
    formatCurrency(value) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value || 0);
    }
    
    formatDate(dateString) {
        if (!dateString) return '';
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        }).format(new Date(dateString));
    }
    
    handleInvoiceSelect(event) {
        const invoiceId = event.target.dataset.id;
        const checked = event.target.checked;
        
        this.invoices = this.invoices.map(inv => {
            if (inv.id === invoiceId) {
                return { ...inv, selected: checked };
            }
            return inv;
        });
        
        if (checked) {
            const invoice = this.invoices.find(i => i.id === invoiceId);
            this.selectedInvoices.set(invoiceId, {
                invoiceId,
                amount: invoice.balanceDue,
                isFullPayment: true
            });
        } else {
            this.selectedInvoices.delete(invoiceId);
        }
        
        this.notifySelectionChange();
    }
    
    handlePaymentTypeChange(event) {
        const invoiceId = event.target.dataset.id;
        const paymentType = event.detail.value;
        
        this.invoices = this.invoices.map(inv => {
            if (inv.id === invoiceId) {
                const isFullPayment = paymentType === 'full';
                const amount = isFullPayment ? inv.balanceDue : inv.paymentAmount;
                
                if (this.selectedInvoices.has(invoiceId)) {
                    this.selectedInvoices.set(invoiceId, {
                        invoiceId,
                        amount,
                        isFullPayment
                    });
                }
                
                return { ...inv, paymentType };
            }
            return inv;
        });
        
        this.notifySelectionChange();
    }
    
    handlePartialAmountChange(event) {
        const invoiceId = event.target.dataset.id;
        const amount = parseFloat(event.target.value) || 0;
        
        this.invoices = this.invoices.map(inv => {
            if (inv.id === invoiceId) {
                const validAmount = Math.min(Math.max(0, amount), inv.balanceDue);
                
                if (this.selectedInvoices.has(invoiceId)) {
                    this.selectedInvoices.set(invoiceId, {
                        invoiceId,
                        amount: validAmount,
                        isFullPayment: false
                    });
                }
                
                return { ...inv, paymentAmount: validAmount };
            }
            return inv;
        });
        
        this.notifySelectionChange();
    }
    
    handleSelectAll(event) {
        const checked = event.target.checked;
        
        this.invoices = this.invoices.map(inv => ({
            ...inv,
            selected: checked
        }));
        
        if (checked) {
            this.invoices.forEach(inv => {
                this.selectedInvoices.set(inv.id, {
                    invoiceId: inv.id,
                    amount: inv.balanceDue,
                    isFullPayment: true
                });
            });
        } else {
            this.selectedInvoices.clear();
        }
        
        this.notifySelectionChange();
    }
    
    notifySelectionChange() {
        const allocations = Array.from(this.selectedInvoices.values());
        const totalAmount = allocations.reduce((sum, a) => sum + a.amount, 0);
        
        this.dispatchEvent(new CustomEvent('selectionchange', {
            detail: {
                allocations,
                totalAmount,
                invoiceCount: allocations.length
            }
        }));
    }
    
    get paymentTypeOptions() {
        return [
            { label: 'Full Payment', value: 'full' },
            { label: 'Partial Payment', value: 'partial' }
        ];
    }
    
    get hasInvoices() {
        return this.invoices.length > 0;
    }
    
    get selectedCount() {
        return this.selectedInvoices.size;
    }
    
    get totalSelectedAmount() {
        let total = 0;
        this.selectedInvoices.forEach(sel => {
            total += sel.amount;
        });
        return this.formatCurrency(total);
    }
    
    get allSelected() {
        return this.invoices.length > 0 && 
               this.invoices.every(inv => inv.selected);
    }
    
    get invoicesWithState() {
        return this.invoices.map(inv => ({
            ...inv,
            rowClass: `invoice-row ${inv.selected ? 'selected' : ''} ${inv.isOverdue ? 'overdue' : ''}`,
            showPartialAmount: inv.selected && inv.paymentType === 'partial',
            statusClass: `slds-badge ${this.getStatusClass(inv.status)}`,
            dueDateClass: inv.isOverdue ? 'overdue-text' : ''
        }));
    }
    
    getStatusClass(status) {
        const statusClasses = {
            'Pending': 'slds-theme_warning',
            'Scheduled': 'slds-theme_info',
            'Partially Paid': 'slds-theme_success',
            'Overdue': 'slds-theme_error',
            'Failed': 'slds-theme_error'
        };
        return statusClasses[status] || '';
    }
    
    @api
    getSelections() {
        return Array.from(this.selectedInvoices.values());
    }
    
    @api
    getTotalAmount() {
        let total = 0;
        this.selectedInvoices.forEach(sel => {
            total += sel.amount;
        });
        return total;
    }
    
    @api
    clearSelections() {
        this.selectedInvoices.clear();
        this.invoices = this.invoices.map(inv => ({
            ...inv,
            selected: false,
            paymentType: 'full',
            paymentAmount: inv.balanceDue
        }));
        this.notifySelectionChange();
    }
}
