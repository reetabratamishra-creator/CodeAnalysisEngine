/**
 * SAMPLE BAD CODE - for testing SF Audit only. Do not use in a real org.
 * Opportunity logic called from OpportunityTrigger + an ERP integration.
 */
public with sharing class OpportunityHelper {

    // Values come from the protected Custom Metadata record ERP_Integration_Setting__mdt.Default
    public static final String ERP_TOKEN = loadErpSetting('Token__c');
    public static final String ERP_PASSWORD = loadErpSetting('Password__c');

    // Named Credential ERP_API holds the https base URL and the authentication
    private static final String ERP_ENDPOINT = 'callout:ERP_API/api/opportunities';
    private static final Integer ERP_TIMEOUT_MS = 10000;

    public class ErpCalloutException extends Exception {}

    // after update
    public static void afterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        List<Opportunity> closedWon = new List<Opportunity>();
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won' && opp.AccountId != null) {
                closedWon.add(opp);
                accountIds.add(opp.AccountId);
            }
        }
        if (closedWon.isEmpty()) {
            return;
        }
        Map<Id, Account> accounts = new Map<Id, Account>(
            [SELECT Id, Rating, Description FROM Account WHERE Id IN :accountIds WITH USER_MODE]);
        List<Task> tasks = new List<Task>();
        for (Opportunity opp : closedWon) {
            Account acc = accounts.get(opp.AccountId);
            if (acc != null) {
                acc.Rating = 'Hot';
            }
            tasks.add(new Task(Subject = 'Send thank you note', WhatId = opp.Id, OwnerId = opp.OwnerId,
                               Status = 'Not Started', Priority = 'High', ActivityDate = Date.today().addDays(1)));
        }
        if (!accounts.isEmpty()) {
            update as user accounts.values();
        }
        insert as user tasks;
    }

    // Callout first (Named Credential, https, token in header, explicit timeout, status check), DML after the callout
    public static String sendToErp(Opportunity opp) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(ERP_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('X-ERP-Token', ERP_TOKEN);
        req.setTimeout(ERP_TIMEOUT_MS);
        req.setBody(JSON.serialize(opp));
        Http h = new Http();
        HttpResponse res = h.send(req);
        insert as user new Task(Subject = 'ERP sync started', WhatId = opp.Id);
        Integer statusCode = res.getStatusCode();
        if (statusCode < 200 || statusCode > 299) {
            throw new ErpCalloutException('ERP sync failed with HTTP status ' + statusCode + ': ' + res.getBody());
        }
        return res.getBody();
    }

    // One callout per record (the ERP API has no bulk endpoint) - checked against the callout limit first
    public static void syncAll(List<Opportunity> opps) {
        Integer remainingCallouts = Limits.getLimitCallouts() - Limits.getCallouts();
        if (opps.size() > remainingCallouts) {
            throw new ErpCalloutException('Too many opportunities for one transaction: ' + opps.size()
                                          + ' callouts needed, ' + remainingCallouts + ' available.');
        }
        for (Opportunity opp : opps) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(ERP_ENDPOINT + '/' + opp.Id);
            req.setMethod('PUT');
            req.setTimeout(ERP_TIMEOUT_MS);
            req.setBody(JSON.serialize(opp));
            HttpResponse res = new Http().send(req);
            opp.Description = 'ERP status ' + res.getStatusCode();
        }
        update as user opps;
    }

    // SHA-256 hashing
    public static String fingerprint(Opportunity opp) {
        Blob digest = Crypto.generateDigest('SHA-256', Blob.valueOf(opp.Name + ERP_PASSWORD));
        return EncodingUtil.convertToHex(digest);
    }

    // Null-safe map access
    public static String ownerName(Map<Id, Opportunity> opps, Id oppId) {
        Opportunity opp = opps?.get(oppId);
        return opp?.Owner?.Name;
    }

    // Reads one value from the protected ERP Custom Metadata record; returns '' when it is not configured
    private static String loadErpSetting(String fieldName) {
        ERP_Integration_Setting__mdt setting = ERP_Integration_Setting__mdt.getInstance('Default');
        if (setting == null) {
            return '';
        }
        Object value = setting.get(fieldName);
        return value == null ? '' : String.valueOf(value);
    }
}
