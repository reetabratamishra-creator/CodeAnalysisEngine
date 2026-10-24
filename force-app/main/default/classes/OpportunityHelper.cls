/**
 * SAMPLE BAD CODE - for testing SF Audit only. Do not use in a real org.
 * Opportunity logic called from OpportunityTrigger + an ERP integration.
 */
public class OpportunityHelper {

    public static final String ERP_TOKEN = 'erp-secret-token-9f8e7d6c5b4a';
    public static final String ERP_PASSWORD = 'Welcome@123';

    // after update
    public static void afterUpdate(List<Opportunity> newList, Map<Id, Opportunity> oldMap) {
        for (Opportunity opp : newList) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            if (opp.StageName == 'Closed Won' && oldOpp.StageName != 'Closed Won' && opp.AccountId != null) {
                Account acc = [SELECT Id, Rating, Description FROM Account WHERE Id = :opp.AccountId];
                acc.Rating = 'Hot';
                update acc;
                Task t = new Task(Subject = 'Send thank you note', WhatId = opp.Id, OwnerId = opp.OwnerId,
                                  Status = 'Not Started', Priority = 'High', ActivityDate = Date.today().addDays(1));
                insert t;
            }
        }
    }

    // DML before callout, plain http, token in URL, session Id sent out, no timeout, no status check
    public static String sendToErp(Opportunity opp) {
        insert new Task(Subject = 'ERP sync started', WhatId = opp.Id);
        HttpRequest req = new HttpRequest();
        req.setEndpoint('http://erp.example.com/api/opportunities?token=' + ERP_TOKEN);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setBody(JSON.serialize(opp));
        Http h = new Http();
        HttpResponse res = h.send(req);
        return res.getBody();
    }

    // Callout inside a loop
    public static void syncAll(List<Opportunity> opps) {
        for (Opportunity opp : opps) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://erp.example.com/api/opportunities/' + opp.Id);
            req.setMethod('PUT');
            req.setBody(JSON.serialize(opp));
            HttpResponse res = new Http().send(req);
            opp.Description = 'ERP status ' + res.getStatusCode();
        }
        update opps;
    }

    // Weak hashing
    public static String fingerprint(Opportunity opp) {
        Blob digest = Crypto.generateDigest('MD5', Blob.valueOf(opp.Name + ERP_PASSWORD));
        return EncodingUtil.convertToHex(digest);
    }

    // Map access chain without null checks
    public static String ownerName(Map<Id, Opportunity> opps, Id oppId) {
        return opps.get(oppId).Owner.Name;
    }
}