/**
 * SAMPLE BAD CODE - for testing SF Audit only.
 * Uses real org data and checks nothing.
 */
@isTest(SeeAllData=true)
private class BadSampleTest {

    @isTest
    static void testAccountService() {
        Account a = new Account(Name = 'Sample Audit Account');
        insert a;
        AccountService.searchAccounts('Sample');
        AccountService.getTopAccount();
    }

    @isTest
    static void testLeadController() {
        List<Lead> leads = LeadController.getHotLeads('Open - Not Contacted');
    }
}