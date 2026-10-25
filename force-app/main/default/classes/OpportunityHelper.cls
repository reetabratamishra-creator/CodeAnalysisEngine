/**
 * SAMPLE BAD CODE - for testing SF Audit only. Do not use in a real org.
 * Opportunity logic called from OpportunityTrigger + an ERP integration.
 */
public with sharing class OpportunityHelper {

    public static final String ERP_TOKEN = readSetting('Token__c');
    public static final String ERP_PASSWORD = readSetting('Password__c');

    private static final String ERP_NAMED_CREDENTIAL = 'callout:ERP_API';
    private static final Integer ERP_TIMEOUT_MS = 20000;

    // after update
    public static void afterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Opportunity> wonOpps = new List<Opportunity>();
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won' && opp.AccountId != null) {
                wonOpps.add(opp);
                accountIds.add(opp.AccountId);
            }
        }
        if (wonOpps.isEmpty()) {
            return;
        }

        Map<Id, Account> accountsById = new Map<Id, Account>(
            [SELECT Id, Rating, Description FROM Account WHERE Id IN :accountIds WITH USER_MODE]
        );
        for (Account acc : accountsById.values()) {
            acc.Rating = 'Hot';
        }

        List<Task> tasks = new List<Task>();
        for (Opportunity opp : wonOpps) {
            tasks.add(new Task(Subject = 'Send thank you note', WhatId = opp.Id, OwnerId = opp.OwnerId,
                               Status = 'Not Started', Priority = 'High', ActivityDate = Date.today().addDays(1)));
        }

        if (!accountsById.isEmpty()) {
            update as user accountsById.values();
        }
        insert as user tasks;
    }

    // Callout first (Named Credential, https, timeout, status check), then DML
    public static String sendToErp(Opportunity opp) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ERP_NAMED_CREDENTIAL + '/api/opportunities');
        req.setMethod('POST');
        req.setTimeout(ERP_TIMEOUT_MS);
        if (String.isNotBlank(ERP_TOKEN)) {
            req.setHeader('X-ERP-Token', ERP_TOKEN);
        }
        req.setBody(JSON.serialize(opp));
        Http h = new Http();
        HttpResponse res = h.send(req);
        insert as user new Task(Subject = 'ERP sync started', WhatId = opp.Id);
        Integer statusCode = res.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            throw new CalloutException('ERP callout failed with status ' + statusCode + ': ' + res.getBody());
        }
        return res.getBody();
    }

    // Callout inside a loop
    // The ERP API is called once per record (no bulk endpoint available); fail fast before the callout limit is hit
    public static void syncAll(List<Opportunity> opps) {
        Integer remainingCallouts = Limits.getLimitCallouts() - Limits.getCallouts();
        if (opps != null && opps.size() > remainingCallouts) {
            throw new CalloutException('syncAll needs ' + opps.size() + ' ERP callouts but only '
                + remainingCallouts + ' remain in this transaction; send smaller batches.');
        }
        for (Opportunity opp : opps) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(ERP_NAMED_CREDENTIAL + '/api/opportunities/' + opp.Id);
            req.setMethod('PUT');
            req.setTimeout(ERP_TIMEOUT_MS);
            req.setBody(JSON.serialize(opp));
            HttpResponse res = new Http().send(req);
            opp.Description = 'ERP status ' + res.getStatusCode();
        }
        update as user opps;
    }

    // Hashing (SHA-256)
    public static String fingerprint(Opportunity opp) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(opp.Name + ERP_PASSWORD));
        return EncodingUtil.convertToHex(digest);
    }

    // Null-safe map access chain
    public static String ownerName(Map<Id, Opportunity> opps, Id oppId) {
        return opps?.get(oppId)?.Owner?.Name;
    }

    // Reads a value from the protected ERP_Integration_Setting__mdt.Default record; '' when not configured
    private static String readSetting(String fieldName) {
        ERP_Integration_Setting__mdt setting = ERP_Integration_Setting__mdt.getInstance('Default');
        if (setting == null) {
            return '';
        }
        Object value = setting.get(fieldName);
        return value == null ? '' : String.valueOf(value);
    }
}
