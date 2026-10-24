/**
 * SAMPLE BAD CODE - for testing SF Audit only. Do not use in a real org.
 * Controller for the LeadSearch Visualforce page and Lightning components.
 */
public without sharing class LeadController {

    public String searchText { get; set; }
    public List<Lead> results { get; set; }

    public LeadController() {
        searchText = ApexPages.currentPage().getParameters().get('q');
        results = new List<Lead>();
    }

    // SOQL injection from a page parameter
    public PageReference search() {
        String soql = 'SELECT Id, FirstName, LastName, Company, Email FROM Lead WHERE Company LIKE \'%' + searchText + '%\'';
        results = Database.query(soql);
        return null;
    }

    // Open redirect - goes to any URL given in the link
    public PageReference goBack() {
        String url = ApexPages.currentPage().getParameters().get('retURL');
        return new PageReference(url);
    }

    // No try/catch around an @AuraEnabled method
    @AuraEnabled
    public static List<Lead> getHotLeads(String status) {
        return [SELECT Id, FirstName, LastName, Company, Rating FROM Lead WHERE Status = :status AND Rating = 'Hot'];
    }

    // Stack trace returned to the user
    @AuraEnabled
    public static String convertLead(Id leadId) {
        try {
            Database.LeadConvert lc = new Database.LeadConvert();
            lc.setLeadId(leadId);
            LeadStatus convertStatus = [SELECT Id, MasterLabel FROM LeadStatus WHERE IsConverted = true LIMIT 1];
            lc.setConvertedStatus(convertStatus.MasterLabel);
            Database.LeadConvertResult lcr = Database.convertLead(lc);
            return lcr.getAccountId();
        } catch (Exception e) {
            return e.getMessage() + '\n' + e.getStackTraceString();
        }
    }

    // Delete without any permission check
    @AuraEnabled
    public static void deleteLead(Id leadId) {
        Lead l = [SELECT Id FROM Lead WHERE Id = :leadId];
        delete l;
    }
}