import { LightningElement, api } from 'lwc';

export default class CardTypeIcon extends LightningElement {
    @api cardBrand;
    @api size = 'medium'; // small, medium, large
    
    get iconClass() {
        const sizeClasses = {
            small: 'card-icon-small',
            medium: 'card-icon-medium',
            large: 'card-icon-large'
        };
        return `card-icon ${sizeClasses[this.size] || 'card-icon-medium'}`;
    }
    
    get brandClass() {
        const brand = (this.cardBrand || '').toLowerCase().replace(/\s+/g, '');
        return `card-brand card-${brand}`;
    }
    
    get brandInitial() {
        const brandMap = {
            'visa': 'V',
            'mastercard': 'MC',
            'americanexpress': 'AX',
            'amex': 'AX',
            'discover': 'D',
            'dinersclub': 'DC',
            'jcb': 'JCB',
            'unionpay': 'UP',
            'unknown': '?'
        };
        const brand = (this.cardBrand || '').toLowerCase().replace(/\s+/g, '');
        return brandMap[brand] || '?';
    }
    
    get brandColor() {
        const colorMap = {
            'visa': '#1A1F71',
            'mastercard': '#EB001B',
            'americanexpress': '#006FCF',
            'amex': '#006FCF',
            'discover': '#FF6600',
            'dinersclub': '#004A97',
            'jcb': '#0B4EA2',
            'unionpay': '#D21920',
            'unknown': '#666666'
        };
        const brand = (this.cardBrand || '').toLowerCase().replace(/\s+/g, '');
        return colorMap[brand] || '#666666';
    }
    
    get iconStyle() {
        return `background-color: ${this.brandColor}`;
    }
}
