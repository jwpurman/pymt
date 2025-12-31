/**
 * @description Authorize.Net payment gateway implementation.
 * Implements the PaymentGateway interface for Authorize.Net API integration.
 * Supports Accept.js tokenization, CIM (Customer Profiles), ACH/eCheck, and Transaction Reporting.
 */
public class AuthorizeNetGateway extends PaymentGatewayBase {
    
    private static final String LIVE_API_URL = 'https://api.authorize.net/xml/v1/request.api';
    private static final String TEST_API_URL = 'https://apitest.authorize.net/xml/v1/request.api';
    private static final String CLIENT_LIBRARY_URL_TEST = 'https://jstest.authorize.net/v1/Accept.js';
    private static final String CLIENT_LIBRARY_URL_LIVE = 'https://js.authorize.net/v1/Accept.js';
    
    private String apiLoginId;
    private String transactionKey;
    
    public AuthorizeNetGateway(Id gatewayId) {
        super(gatewayId);
    }
    
    public AuthorizeNetGateway(pymtTest__Payment_Gateway__c gateway) {
        super(gateway);
    }
    
    protected override void initializeFromConfig() {
        super.initializeFromConfig();
        loadCredentials();
    }
    
    private void loadCredentials() {
        // In production, load from Named Credential or Protected Custom Metadata
        // Example using custom metadata:
        String metadataName = this.isTestMode ? 'AuthNet_Test' : 'AuthNet_Live';
        
        List<pymtTest__Gateway_Credential__mdt> creds = [
            SELECT pymtTest__API_Login_Id__c, pymtTest__Transaction_Key__c
            FROM pymtTest__Gateway_Credential__mdt
            WHERE DeveloperName = :metadataName
            LIMIT 1
        ];
        
        if (!creds.isEmpty()) {
            this.apiLoginId = creds[0].pymtTest__API_Login_Id__c;
            this.transactionKey = creds[0].pymtTest__Transaction_Key__c;
        }
    }
    
    public override String getGatewayType() {
        return 'Authorize.Net';
    }
    
    protected override String getApiBaseUrl() {
        return this.isTestMode ? TEST_API_URL : LIVE_API_URL;
    }
    
    protected override String getSecureApiKey() {
        return this.transactionKey;
    }
    
    protected override void setAuthorizationHeader(HttpRequest request) {
        request.setHeader('Content-Type', 'application/json');
    }
    
    public override String getClientLibraryUrl() {
        return this.isTestMode ? CLIENT_LIBRARY_URL_TEST : CLIENT_LIBRARY_URL_LIVE;
    }
    
    public String getApiLoginId() {
        return this.apiLoginId;
    }
    
    public override String getPublicKey() {
        return this.publicKey; // Client Key for Accept.js
    }
    
    // ==================== Transaction Methods ====================
    
    public override PaymentResponse sale(PaymentRequest request) {
        return processTransaction('authCaptureTransaction', request);
    }
    
    public override PaymentResponse authorize(PaymentRequest request) {
        return processTransaction('authOnlyTransaction', request);
    }
    
    public override PaymentResponse capture(String transactionId, Decimal amount) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> transactionRequest = new Map<String, Object>{
                'transactionType' => 'priorAuthCaptureTransaction',
                'refTransId' => transactionId
            };
            
            if (amount != null) {
                transactionRequest.put('amount', amount);
            }
            
            requestBody.put('transactionRequest', transactionRequest);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createTransactionRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    public override PaymentResponse refund(String transactionId, Decimal amount) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> transactionRequest = new Map<String, Object>{
                'transactionType' => 'refundTransaction',
                'refTransId' => transactionId
            };
            
            if (amount != null) {
                transactionRequest.put('amount', amount);
            }
            
            requestBody.put('transactionRequest', transactionRequest);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createTransactionRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    public override PaymentResponse voidTransaction(String transactionId) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> transactionRequest = new Map<String, Object>{
                'transactionType' => 'voidTransaction',
                'refTransId' => transactionId
            };
            
            requestBody.put('transactionRequest', transactionRequest);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createTransactionRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    private PaymentResponse processTransaction(String transactionType, PaymentRequest request) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> transactionRequest = new Map<String, Object>{
                'transactionType' => transactionType,
                'amount' => request.amount
            };
            
            // Payment method - Accept.js token or customer profile
            if (String.isNotBlank(request.cardToken)) {
                // Accept.js token format: dataDescriptor:dataValue
                List<String> tokenParts = request.cardToken.split(':');
                if (tokenParts.size() == 2) {
                    transactionRequest.put('payment', new Map<String, Object>{
                        'opaqueData' => new Map<String, Object>{
                            'dataDescriptor' => tokenParts[0],
                            'dataValue' => tokenParts[1]
                        }
                    });
                }
            } else if (String.isNotBlank(request.paymentMethodToken)) {
                // Customer Profile - token format: customerProfileId:paymentProfileId
                List<String> profileParts = request.paymentMethodToken.split(':');
                if (profileParts.size() == 2) {
                    transactionRequest.put('profile', new Map<String, Object>{
                        'customerProfileId' => profileParts[0],
                        'paymentProfile' => new Map<String, Object>{
                            'paymentProfileId' => profileParts[1]
                        }
                    });
                }
            }
            
            // Order information
            if (String.isNotBlank(request.description)) {
                transactionRequest.put('order', new Map<String, Object>{
                    'description' => request.description.abbreviate(255)
                });
            }
            
            // Billing address
            if (String.isNotBlank(request.billingStreet)) {
                transactionRequest.put('billTo', new Map<String, Object>{
                    'firstName' => getFirstName(request.billingName),
                    'lastName' => getLastName(request.billingName),
                    'address' => request.billingStreet,
                    'city' => request.billingCity,
                    'state' => request.billingState,
                    'zip' => request.billingPostalCode,
                    'country' => request.billingCountry
                });
            }
            
            // Duplicate window (idempotency)
            transactionRequest.put('transactionSettings', new Map<String, Object>{
                'setting' => new List<Object>{
                    new Map<String, Object>{
                        'settingName' => 'duplicateWindow',
                        'settingValue' => '120'
                    }
                }
            });
            
            requestBody.put('transactionRequest', transactionRequest);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createTransactionRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionResponse(response);
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    // ==================== Customer Profile (CIM) Methods ====================
    
    public override CustomerResponse createCustomer(CustomerRequest customerRequest) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> profile = new Map<String, Object>{
                'merchantCustomerId' => customerRequest.accountId != null ? 
                    String.valueOf(customerRequest.accountId) : generateCustomerId(),
                'email' => customerRequest.email,
                'description' => customerRequest.description
            };
            
            requestBody.put('profile', profile);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createCustomerProfileRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseCustomerResponse(response);
            
        } catch (Exception e) {
            return CustomerResponse.failure('SYSTEM_ERROR', e.getMessage());
        }
    }
    
    public override PaymentMethodResponse attachPaymentMethod(String customerId, String paymentMethodToken) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            requestBody.put('customerProfileId', customerId);
            
            List<String> tokenParts = paymentMethodToken.split(':');
            if (tokenParts.size() != 2) {
                return PaymentMethodResponse.failure('INVALID_TOKEN', 'Invalid payment token format');
            }
            
            Map<String, Object> paymentProfile = new Map<String, Object>{
                'payment' => new Map<String, Object>{
                    'opaqueData' => new Map<String, Object>{
                        'dataDescriptor' => tokenParts[0],
                        'dataValue' => tokenParts[1]
                    }
                }
            };
            
            requestBody.put('paymentProfile', paymentProfile);
            requestBody.put('validationMode', this.isTestMode ? 'testMode' : 'liveMode');
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createCustomerPaymentProfileRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parsePaymentProfileResponse(response);
            
        } catch (Exception e) {
            return PaymentMethodResponse.failure('SYSTEM_ERROR', e.getMessage());
        }
    }
    
    public override TokenResponse createToken(TokenRequest tokenRequest) {
        return TokenResponse.failure('USE_ACCEPT_JS', 
            'Card tokenization must be done client-side using Accept.js.');
    }
    
    // ==================== Transaction Status/Settlement Methods ====================
    
    /**
     * @description Get transaction details including settlement status
     */
    public TransactionDetails getTransactionDetails(String transactionId) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            requestBody.put('transId', transactionId);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'getTransactionDetailsRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionDetails(response);
            
        } catch (Exception e) {
            TransactionDetails details = new TransactionDetails();
            details.success = false;
            details.errorMessage = e.getMessage();
            return details;
        }
    }
    
    /**
     * @description Get list of unsettled transactions
     */
    public List<TransactionDetails> getUnsettledTransactions() {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'getUnsettledTransactionListRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionList(response);
            
        } catch (Exception e) {
            return new List<TransactionDetails>();
        }
    }
    
    /**
     * @description Get settled batches for a date range
     */
    public List<BatchDetails> getSettledBatches(Date startDate, Date endDate) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            requestBody.put('firstSettlementDate', formatDate(startDate));
            requestBody.put('lastSettlementDate', formatDate(endDate));
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'getSettledBatchListRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseBatchList(response);
            
        } catch (Exception e) {
            return new List<BatchDetails>();
        }
    }
    
    /**
     * @description Get transactions in a settled batch
     */
    public List<TransactionDetails> getBatchTransactions(String batchId) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            requestBody.put('batchId', batchId);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'getTransactionListRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parseTransactionList(response);
            
        } catch (Exception e) {
            return new List<TransactionDetails>();
        }
    }
    
    // ==================== ACH/eCheck Methods ====================
    
    /**
     * @description Process an ACH/eCheck payment
     */
    public PaymentResponse processACHPayment(ACHPaymentRequest request) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            
            Map<String, Object> transactionRequest = new Map<String, Object>{
                'transactionType' => 'authCaptureTransaction',
                'amount' => request.amount,
                'payment' => new Map<String, Object>{
                    'bankAccount' => new Map<String, Object>{
                        'accountType' => request.accountType,
                        'routingNumber' => request.routingNumber,
                        'accountNumber' => request.accountNumber,
                        'nameOnAccount' => request.nameOnAccount,
                        'echeckType' => request.echeckType,
                        'bankName' => request.bankName
                    }
                }
            };
            
            if (String.isNotBlank(request.billingName)) {
                transactionRequest.put('billTo', new Map<String, Object>{
                    'firstName' => getFirstName(request.billingName),
                    'lastName' => getLastName(request.billingName),
                    'address' => request.billingStreet,
                    'city' => request.billingCity,
                    'state' => request.billingState,
                    'zip' => request.billingPostalCode
                });
            }
            
            requestBody.put('transactionRequest', transactionRequest);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createTransactionRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            PaymentResponse result = parseTransactionResponse(response);
            
            if (result.success) {
                result.additionalData.put('paymentType', 'ACH');
                result.additionalData.put('expectedSettlementDate', 
                    String.valueOf(calculateACHSettlementDate(Date.today())));
            }
            
            return result;
            
        } catch (Exception e) {
            return PaymentResponse.error(e.getMessage());
        }
    }
    
    /**
     * @description Create ACH payment method on customer profile
     */
    public PaymentMethodResponse addACHPaymentMethod(String customerId, ACHPaymentRequest achRequest) {
        try {
            Map<String, Object> requestBody = buildMerchantAuth();
            requestBody.put('customerProfileId', customerId);
            
            Map<String, Object> paymentProfile = new Map<String, Object>{
                'payment' => new Map<String, Object>{
                    'bankAccount' => new Map<String, Object>{
                        'accountType' => achRequest.accountType,
                        'routingNumber' => achRequest.routingNumber,
                        'accountNumber' => achRequest.accountNumber,
                        'nameOnAccount' => achRequest.nameOnAccount,
                        'echeckType' => achRequest.echeckType,
                        'bankName' => achRequest.bankName
                    }
                }
            };
            
            requestBody.put('paymentProfile', paymentProfile);
            
            Map<String, Object> wrapper = new Map<String, Object>{
                'createCustomerPaymentProfileRequest' => requestBody
            };
            
            HttpResponse response = makeAuthNetCallout(JSON.serialize(wrapper));
            return parsePaymentProfileResponse(response);
            
        } catch (Exception e) {
            return PaymentMethodResponse.failure('SYSTEM_ERROR', e.getMessage());
        }
    }
    
    // ==================== Helper Methods ====================
    
    private Map<String, Object> buildMerchantAuth() {
        return new Map<String, Object>{
            'merchantAuthentication' => new Map<String, Object>{
                'name' => this.apiLoginId,
                'transactionKey' => this.transactionKey
            }
        };
    }
    
    private HttpResponse makeAuthNetCallout(String body) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        request.setEndpoint(getApiBaseUrl());
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(120000);
        request.setBody(body);
        
        logRequest('POST', getApiBaseUrl(), maskSensitiveData(body));
        
        HttpResponse response = http.send(request);
        logResponse(response);
        
        return response;
    }
    
    private String maskSensitiveData(String body) {
        body = body.replaceAll('"transactionKey"\\s*:\\s*"[^"]*"', '"transactionKey":"***"');
        body = body.replaceAll('"accountNumber"\\s*:\\s*"[^"]*"', '"accountNumber":"***"');
        body = body.replaceAll('"routingNumber"\\s*:\\s*"[^"]*"', '"routingNumber":"***"');
        body = body.replaceAll('"dataValue"\\s*:\\s*"[^"]*"', '"dataValue":"***"');
        return body;
    }
    
    private PaymentResponse parseTransactionResponse(HttpResponse response) {
        PaymentResponse result = new PaymentResponse();
        
        String responseBody = cleanResponse(response.getBody());
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        result.rawResponse = responseBody;
        
        Map<String, Object> transactionResponse = (Map<String, Object>) jsonResponse.get('transactionResponse');
        Map<String, Object> messages = (Map<String, Object>) jsonResponse.get('messages');
        
        if (messages != null) {
            String resultCode = (String) messages.get('resultCode');
            
            if (resultCode == 'Ok' && transactionResponse != null) {
                String responseCode = String.valueOf(transactionResponse.get('responseCode'));
                
                if (responseCode == '1') {
                    result.success = true;
                    result.transactionId = (String) transactionResponse.get('transId');
                    result.status = 'Approved';
                    
                    String accountNumber = (String) transactionResponse.get('accountNumber');
                    String accountType = (String) transactionResponse.get('accountType');
                    
                    if (String.isNotBlank(accountNumber)) {
                        result.cardLast4 = accountNumber.right(4);
                    }
                    if (String.isNotBlank(accountType)) {
                        result.cardBrand = mapAccountType(accountType);
                    }
                    
                } else {
                    result.success = false;
                    result.status = 'Declined';
                    
                    List<Object> errors = (List<Object>) transactionResponse.get('errors');
                    if (errors != null && !errors.isEmpty()) {
                        Map<String, Object> error = (Map<String, Object>) errors[0];
                        result.errorCode = String.valueOf(error.get('errorCode'));
                        result.errorMessage = (String) error.get('errorText');
                    }
                }
            } else {
                result.success = false;
                result.status = 'Error';
                
                List<Object> messageList = (List<Object>) messages.get('message');
                if (messageList != null && !messageList.isEmpty()) {
                    Map<String, Object> msg = (Map<String, Object>) messageList[0];
                    result.errorCode = (String) msg.get('code');
                    result.errorMessage = (String) msg.get('text');
                }
            }
        }
        
        return result;
    }
    
    private CustomerResponse parseCustomerResponse(HttpResponse response) {
        String responseBody = cleanResponse(response.getBody());
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> messages = (Map<String, Object>) jsonResponse.get('messages');
        
        if (messages != null && messages.get('resultCode') == 'Ok') {
            String customerId = (String) jsonResponse.get('customerProfileId');
            return CustomerResponse.success(customerId);
        } else {
            return extractError(messages);
        }
    }
    
    private CustomerResponse extractError(Map<String, Object> messages) {
        String errorMessage = 'Unknown error';
        String errorCode = 'UNKNOWN';
        
        if (messages != null) {
            List<Object> messageList = (List<Object>) messages.get('message');
            if (messageList != null && !messageList.isEmpty()) {
                Map<String, Object> msg = (Map<String, Object>) messageList[0];
                errorCode = (String) msg.get('code');
                errorMessage = (String) msg.get('text');
            }
        }
        
        return CustomerResponse.failure(errorCode, errorMessage);
    }
    
    private PaymentMethodResponse parsePaymentProfileResponse(HttpResponse response) {
        String responseBody = cleanResponse(response.getBody());
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> messages = (Map<String, Object>) jsonResponse.get('messages');
        
        if (messages != null && messages.get('resultCode') == 'Ok') {
            String paymentProfileId = (String) jsonResponse.get('customerPaymentProfileId');
            return PaymentMethodResponse.success(paymentProfileId);
        } else {
            String errorMessage = 'Unknown error';
            String errorCode = 'UNKNOWN';
            
            if (messages != null) {
                List<Object> messageList = (List<Object>) messages.get('message');
                if (messageList != null && !messageList.isEmpty()) {
                    Map<String, Object> msg = (Map<String, Object>) messageList[0];
                    errorCode = (String) msg.get('code');
                    errorMessage = (String) msg.get('text');
                }
            }
            
            return PaymentMethodResponse.failure(errorCode, errorMessage);
        }
    }
    
    private TransactionDetails parseTransactionDetails(HttpResponse response) {
        TransactionDetails details = new TransactionDetails();
        
        String responseBody = cleanResponse(response.getBody());
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> messages = (Map<String, Object>) jsonResponse.get('messages');
        
        if (messages != null && messages.get('resultCode') == 'Ok') {
            details.success = true;
            
            Map<String, Object> txn = (Map<String, Object>) jsonResponse.get('transaction');
            if (txn != null) {
                details.transactionId = (String) txn.get('transId');
                details.transactionStatus = (String) txn.get('transactionStatus');
                details.settlementState = (String) txn.get('settlementState');
                
                Object amountObj = txn.get('settleAmount');
                if (amountObj != null) {
                    details.settleAmount = Decimal.valueOf(String.valueOf(amountObj));
                }
                
                String submitDate = (String) txn.get('submitTimeUTC');
                if (String.isNotBlank(submitDate)) {
                    details.submitDate = parseAuthNetDate(submitDate);
                }
                
                Map<String, Object> batch = (Map<String, Object>) txn.get('batch');
                if (batch != null) {
                    details.batchId = (String) batch.get('batchId');
                    String settlementDate = (String) batch.get('settlementTimeUTC');
                    if (String.isNotBlank(settlementDate)) {
                        details.settlementDate = parseAuthNetDate(settlementDate);
                    }
                    details.settlementState = (String) batch.get('settlementState');
                }
                
                // Check for ACH returns
                List<Object> returnedItems = (List<Object>) txn.get('returnedItems');
                if (returnedItems != null && !returnedItems.isEmpty()) {
                    details.isReturned = true;
                    Map<String, Object> returnItem = (Map<String, Object>) returnedItems[0];
                    details.returnReasonCode = (String) returnItem.get('code');
                    details.returnDescription = (String) returnItem.get('description');
                }
            }
        } else {
            details.success = false;
            if (messages != null) {
                List<Object> messageList = (List<Object>) messages.get('message');
                if (messageList != null && !messageList.isEmpty()) {
                    Map<String, Object> msg = (Map<String, Object>) messageList[0];
                    details.errorMessage = (String) msg.get('text');
                }
            }
        }
        
        return details;
    }
    
    private List<TransactionDetails> parseTransactionList(HttpResponse response) {
        List<TransactionDetails> transactions = new List<TransactionDetails>();
        
        String responseBody = cleanResponse(response.getBody());
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> messages = (Map<String, Object>) jsonResponse.get('messages');
        
        if (messages != null && messages.get('resultCode') == 'Ok') {
            List<Object> txnList = (List<Object>) jsonResponse.get('transactions');
            if (txnList != null) {
                for (Object txnObj : txnList) {
                    Map<String, Object> txn = (Map<String, Object>) txnObj;
                    TransactionDetails details = new TransactionDetails();
                    details.success = true;
                    details.transactionId = (String) txn.get('transId');
                    details.transactionStatus = (String) txn.get('transactionStatus');
                    
                    Object amountObj = txn.get('settleAmount');
                    if (amountObj != null) {
                        details.settleAmount = Decimal.valueOf(String.valueOf(amountObj));
                    }
                    
                    transactions.add(details);
                }
            }
        }
        
        return transactions;
    }
    
    private List<BatchDetails> parseBatchList(HttpResponse response) {
        List<BatchDetails> batches = new List<BatchDetails>();
        
        String responseBody = cleanResponse(response.getBody());
        Map<String, Object> jsonResponse = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        Map<String, Object> messages = (Map<String, Object>) jsonResponse.get('messages');
        
        if (messages != null && messages.get('resultCode') == 'Ok') {
            List<Object> batchList = (List<Object>) jsonResponse.get('batchList');
            if (batchList != null) {
                for (Object batchObj : batchList) {
                    Map<String, Object> batch = (Map<String, Object>) batchObj;
                    BatchDetails details = new BatchDetails();
                    details.batchId = (String) batch.get('batchId');
                    details.settlementState = (String) batch.get('settlementState');
                    
                    String settlementDate = (String) batch.get('settlementTimeUTC');
                    if (String.isNotBlank(settlementDate)) {
                        details.settlementDate = parseAuthNetDate(settlementDate);
                    }
                    
                    batches.add(details);
                }
            }
        }
        
        return batches;
    }
    
    private String cleanResponse(String responseBody) {
        // Remove BOM if present
        if (responseBody.startsWith('\uFEFF')) {
            responseBody = responseBody.substring(1);
        }
        return responseBody;
    }
    
    private DateTime parseAuthNetDate(String dateStr) {
        try {
            return (DateTime) JSON.deserialize('"' + dateStr + '"', DateTime.class);
        } catch (Exception e) {
            return null;
        }
    }
    
    private String formatDate(Date d) {
        return String.valueOf(d) + 'T00:00:00Z';
    }
    
    private String mapAccountType(String accountType) {
        Map<String, String> typeMap = new Map<String, String>{
            'Visa' => 'Visa',
            'MasterCard' => 'Mastercard',
            'AmericanExpress' => 'American Express',
            'Discover' => 'Discover',
            'JCB' => 'JCB',
            'DinersClub' => 'Diners Club',
            'eCheck' => 'ACH'
        };
        return typeMap.containsKey(accountType) ? typeMap.get(accountType) : accountType;
    }
    
    private String getFirstName(String fullName) {
        if (String.isBlank(fullName)) return '';
        List<String> parts = fullName.split(' ');
        return parts[0];
    }
    
    private String getLastName(String fullName) {
        if (String.isBlank(fullName)) return '';
        List<String> parts = fullName.split(' ');
        return parts.size() > 1 ? parts[parts.size() - 1] : '';
    }
    
    private String generateCustomerId() {
        return 'SF-' + String.valueOf(DateTime.now().getTime());
    }
    
    private Date calculateACHSettlementDate(Date submissionDate) {
        Integer businessDays = 4;
        Date settlementDate = submissionDate;
        Integer daysAdded = 0;
        
        while (daysAdded < businessDays) {
            settlementDate = settlementDate.addDays(1);
            Datetime dt = DateTime.newInstance(settlementDate, Time.newInstance(0, 0, 0, 0));
            String dayOfWeek = dt.format('E');
            if (dayOfWeek != 'Sat' && dayOfWeek != 'Sun') {
                daysAdded++;
            }
        }
        
        return settlementDate;
    }
    
    // ==================== Inner Classes ====================
    
    public class TransactionDetails {
        @AuraEnabled public Boolean success { get; set; }
        @AuraEnabled public String transactionId { get; set; }
        @AuraEnabled public String transactionStatus { get; set; }
        @AuraEnabled public String settlementState { get; set; }
        @AuraEnabled public Decimal settleAmount { get; set; }
        @AuraEnabled public DateTime submitDate { get; set; }
        @AuraEnabled public DateTime settlementDate { get; set; }
        @AuraEnabled public String batchId { get; set; }
        @AuraEnabled public Boolean isReturned { get; set; }
        @AuraEnabled public String returnReasonCode { get; set; }
        @AuraEnabled public String returnDescription { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        
        public TransactionDetails() {
            this.success = false;
            this.isReturned = false;
        }
    }
    
    public class BatchDetails {
        @AuraEnabled public String batchId { get; set; }
        @AuraEnabled public String settlementState { get; set; }
        @AuraEnabled public DateTime settlementDate { get; set; }
    }
    
    public class ACHPaymentRequest {
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public String accountType { get; set; }
        @AuraEnabled public String routingNumber { get; set; }
        @AuraEnabled public String accountNumber { get; set; }
        @AuraEnabled public String nameOnAccount { get; set; }
        @AuraEnabled public String echeckType { get; set; }
        @AuraEnabled public String bankName { get; set; }
        @AuraEnabled public String billingName { get; set; }
        @AuraEnabled public String billingStreet { get; set; }
        @AuraEnabled public String billingCity { get; set; }
        @AuraEnabled public String billingState { get; set; }
        @AuraEnabled public String billingPostalCode { get; set; }
    }
}
