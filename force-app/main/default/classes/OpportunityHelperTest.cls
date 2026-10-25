@isTest
private class OpportunityHelperTest {

    private class ErpMock implements HttpCalloutMock {
        private Integer statusCode;
        private String body;

        ErpMock(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }

        public HttpResponse respond(HttpRequest req) {
            System.assert(req.getEndpoint().startsWith('callout:ERP_API/api/opportunities'),
                'Callout must use the ERP_API Named Credential');
            System.assertEquals(20000, req.getTimeout(), 'Timeout must be set explicitly');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody(body);
            return res;
        }
    }

    @TestSetup
    static void setup() {
        Account acc = new Account(Name = 'Helper Test Account', Rating = 'Cold');
        insert acc;
        insert new Opportunity(Name = 'Helper Test Opp', StageName = 'Prospecting',
                               CloseDate = Date.today().addDays(30), AccountId = acc.Id);
    }

    private static Opportunity getOpp() {
        return [SELECT Id, Name, StageName, AccountId, OwnerId, Owner.Name, Description
                FROM Opportunity WHERE Name = 'Helper Test Opp' LIMIT 1];
    }

    @isTest
    static void afterUpdateMarksAccountHotAndCreatesTask() {
        Opportunity opp = getOpp();
        Opportunity oldOpp = opp.clone(true, true, true, true);
        Opportunity newOpp = opp.clone(true, true, true, true);
        newOpp.StageName = 'Closed Won';

        Test.startTest();
        OpportunityHelper.afterUpdate(new List<Opportunity>{ newOpp }, new Map<Id, Opportunity>{ opp.Id => oldOpp });
        Test.stopTest();

        Account acc = [SELECT Rating FROM Account WHERE Id = :opp.AccountId];
        System.assertEquals('Hot', acc.Rating, 'Account should be rated Hot');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id AND Subject = 'Send thank you note'],
            'One thank-you task expected');
    }

    @isTest
    static void afterUpdateIgnoresUnchangedStage() {
        Opportunity opp = getOpp();
        Opportunity oldOpp = opp.clone(true, true, true, true);

        Test.startTest();
        OpportunityHelper.afterUpdate(new List<Opportunity>{ opp }, new Map<Id, Opportunity>{ opp.Id => oldOpp });
        Test.stopTest();

        Account acc = [SELECT Rating FROM Account WHERE Id = :opp.AccountId];
        System.assertEquals('Cold', acc.Rating, 'Account must not change');
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id], 'No task expected');
    }

    @isTest
    static void sendToErpReturnsBodyAndLogsTask() {
        Opportunity opp = getOpp();
        Test.setMock(HttpCalloutMock.class, new ErpMock(200, '{"status":"ok"}'));

        Test.startTest();
        String body = OpportunityHelper.sendToErp(opp);
        Test.stopTest();

        System.assertEquals('{"status":"ok"}', body, 'Response body should be returned');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :opp.Id AND Subject = 'ERP sync started'],
            'Sync task expected');
    }

    @isTest
    static void sendToErpThrowsOnErrorStatus() {
        Opportunity opp = getOpp();
        Test.setMock(HttpCalloutMock.class, new ErpMock(500, 'Server error'));

        Boolean thrown = false;
        Test.startTest();
        try {
            OpportunityHelper.sendToErp(opp);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('500'), 'Message should contain the status code');
        }
        Test.stopTest();

        System.assert(thrown, 'CalloutException expected for a 500 response');
    }

    @isTest
    static void syncAllWritesStatusToDescription() {
        Opportunity opp = getOpp();
        Test.setMock(HttpCalloutMock.class, new ErpMock(200, '{}'));

        Test.startTest();
        OpportunityHelper.syncAll(new List<Opportunity>{ opp });
        Test.stopTest();

        System.assertEquals('ERP status 200', [SELECT Description FROM Opportunity WHERE Id = :opp.Id].Description,
            'Description should hold the ERP status');
    }

    @isTest
    static void syncAllFailsFastAboveCalloutLimit() {
        Opportunity opp = getOpp();
        Test.setMock(HttpCalloutMock.class, new ErpMock(200, '{}'));
        List<Opportunity> tooMany = new List<Opportunity>();
        for (Integer i = 0; i <= Limits.getLimitCallouts(); i++) {
            tooMany.add(opp);
        }

        Boolean thrown = false;
        Test.startTest();
        try {
            OpportunityHelper.syncAll(tooMany);
        } catch (CalloutException e) {
            thrown = true;
            System.assert(e.getMessage().contains('syncAll'), 'Message should explain the callout budget');
        }
        System.assertEquals(0, Limits.getCallouts(), 'No callout may be sent when the batch is too large');
        Test.stopTest();

        System.assert(thrown, 'CalloutException expected when the batch exceeds the callout limit');
        System.assertEquals(null, [SELECT Description FROM Opportunity WHERE Id = :opp.Id].Description,
            'Opportunity must not be updated');
    }

    @isTest
    static void fingerprintUsesSha256() {
        Opportunity opp = getOpp();
        String fp = OpportunityHelper.fingerprint(opp);
        System.assertEquals(64, fp.length(), 'SHA-256 hex digest has 64 characters');
        System.assertEquals(fp, OpportunityHelper.fingerprint(opp), 'Fingerprint must be deterministic');
    }

    @isTest
    static void ownerNameIsNullSafe() {
        Opportunity opp = getOpp();
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>{ opp.Id => opp };
        System.assertEquals(opp.Owner.Name, OpportunityHelper.ownerName(opps, opp.Id), 'Owner name expected');
        System.assertEquals(null, OpportunityHelper.ownerName(new Map<Id, Opportunity>(), opp.Id),
            'Missing key returns null');
        System.assertEquals(null, OpportunityHelper.ownerName(null, opp.Id), 'Null map returns null');
    }

    @isTest
    static void secretsAreNeverNull() {
        System.assertNotEquals(null, OpportunityHelper.ERP_TOKEN, 'Token must not be null');
        System.assertNotEquals(null, OpportunityHelper.ERP_PASSWORD, 'Password must not be null');
    }
}
