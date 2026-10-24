/**
 * SAMPLE BAD CODE - for testing SF Audit only. Do not use in a real org.
 * Async jobs that push Accounts and Leads to outside systems.
 */
public class IntegrationSyncJob implements Queueable, Schedulable {

    private List<Id> accountIds;

    public IntegrationSyncJob(List<Id> accountIds) {
        this.accountIds = accountIds;
    }

    // Queueable makes callouts but does not implement Database.AllowsCallouts
    public void execute(QueueableContext ctx) {
        for (Account acc : [SELECT Id, Name, Phone, Website FROM Account WHERE Id IN :accountIds]) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('https://api.partner-crm.com/v1/accounts/' + acc.Id);
            req.setMethod('PUT');
            req.setBody(JSON.serialize(acc));
            HttpResponse res = new Http().send(req);
            acc.Description = res.getBody();
            update acc;
        }
    }

    // Queries every Account with no filter
    public void execute(SchedulableContext sc) {
        List<Id> ids = new List<Id>();
        for (Account a : [SELECT Id FROM Account]) {
            ids.add(a.Id);
        }
        System.enqueueJob(new IntegrationSyncJob(ids));
    }

    // @future without callout=true, but it makes callouts
    @future
    public static void pushLeads(Set<Id> leadIds) {
        for (Lead l : [SELECT Id, Email, Company FROM Lead WHERE Id IN :leadIds]) {
            HttpRequest req = new HttpRequest();
            req.setEndpoint('http://marketing.example.com/leads');
            req.setMethod('POST');
            req.setBody('{"email":"' + l.Email + '","company":"' + l.Company + '"}');
            HttpResponse res = new Http().send(req);
        }
    }
}