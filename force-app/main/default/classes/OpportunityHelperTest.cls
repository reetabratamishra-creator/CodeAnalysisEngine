@isTest
private class OpportunityHelperTest {

    private class ErpMock implements HttpCalloutMock {
        private Integer statusCode;
        ErpMock(Integer statusCode) {
            this.statusCode = statusCode;
        }
        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().startsWith('callout:ERP_API/api/opportunities'), 'Named Credential endpoint expected');
            System.assertEquals(10000, req.getTimeout(), 'Explicit timeout expected');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody('{"ok":true}');
            return res;
        }
    }

    private static Opportunity createOpportunity(Id accountId) {
        Opportunity opp = new Opportunity(Name = 'Helper Test Opp', StageName = 'Prospecting',
                                          CloseDate = Date.today().addDays(30), AccountId = accountId);
        insert opp;
        return [SELECT Id, Name, StageName, AccountId, OwnerId, Description FROM Opportunity WHERE Id = :opp.Id];
    }

    @isTest
    static void afterUpdateSetsRatingAndCreatesTask() {
        Account acc = new Account(Name = 'Helper Test Account');
        insert acc;
        Opportunity opp = createOpportunity(acc.Id);
        Opportunity oldOpp = opp.clone(true, true, false, false);
        Opportunity newOpp = opp.clone(true, true, false, false);
        newOpp.StageName = 'Closed Won';

        Test.startTest();
        OpportunityHelper.afterUpdate(new List<Opportunity>{ newOpp }, new Map<Id, Opportunity>{ opp.Id => oldOpp });
        Test.stopTest();

        System.assertEquals('Hot', [SELECT Rating FROM Account WHERE Id = :acc.Id].Rating, 'Account should be rated Hot');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id AND Subject = 'Send thank you note'],
                            'One thank you task expected');
    }

    @isTest
    static void afterUpdateIgnoresUnchangedStage() {
        Account acc = new Account(Name = 'Helper Test Account');
        insert acc;
        Opportunity opp = createOpportunity(acc.Id);

        Test.startTest();
        OpportunityHelper.afterUpdate(new List<Opportunity>{ opp }, new Map<Id, Opportunity>{ opp.Id => opp });
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id], 'No task expected');
        System.assertNotEquals('Hot', [SELECT Rating FROM Account WHERE Id = :acc.Id].Rating, 'Rating must not change');
    }

    @isTest
    static void sendToErpReturnsBodyAndCreatesTask() {
        Opportunity opp = createOpportunity(null);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ErpMock(200));
        String body = OpportunityHelper.sendToErp(opp);
        Test.stopTest();

        System.assertEquals('{"ok":true}', body, 'Response body expected');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id AND Subject = 'ERP sync started'],
                            'Sync task expected');
    }

    @isTest
    static void sendToErpThrowsOnErrorStatus() {
        Opportunity opp = createOpportunity(null);
        Boolean thrown = false;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ErpMock(500));
        try {
            OpportunityHelper.sendToErp(opp);
        } catch (OpportunityHelper.ErpCalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('500'), 'Status code should be in the message');
        }
        Test.stopTest();

        System.assert(thrown, 'ErpCalloutException expected for HTTP 500');
    }

    @isTest
    static void syncAllWritesStatusToDescription() {
        Opportunity opp = createOpportunity(null);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new ErpMock(200));
        OpportunityHelper.syncAll(new List<Opportunity>{ opp });
        Test.stopTest();

        System.assertEquals('ERP status 200', [SELECT Description FROM Opportunity WHERE Id = :opp.Id].Description,
                            'ERP status should be stored');
    }

    @isTest
    static void fingerprintIsSha256Hex() {
        Opportunity opp = new Opportunity(Name = 'Fingerprint Opp');
        String first = OpportunityHelper.fingerprint(opp);
        String second = OpportunityHelper.fingerprint(opp);
        System.assertEquals(64, first.length(), 'SHA-256 hex digest has 64 characters');
        System.assertEquals(first, second, 'Fingerprint must be deterministic');
    }

    @isTest
    static void ownerNameIsNullSafe() {
        Opportunity inserted = createOpportunity(null);
        Opportunity opp = [SELECT Id, Owner.Name FROM Opportunity WHERE Id = :inserted.Id];
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>{ opp.Id => opp };

        System.assertEquals(opp.Owner.Name, OpportunityHelper.ownerName(opps, opp.Id), 'Owner name expected');
        System.assertEquals(null, OpportunityHelper.ownerName(new Map<Id, Opportunity>(), opp.Id), 'Missing key returns null');
        System.assertEquals(null, OpportunityHelper.ownerName(null, opp.Id), 'Null map returns null');
    }
}
