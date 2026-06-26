@isTest
private class GetOpenQuotesForAccountTest {

    @isTest
    static void returnsQuotesForAccount() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();

        GetOpenQuotesForAccount.Request req = new GetOpenQuotesForAccount.Request();
        req.accountId = ctx.account.Id;

        Test.startTest();
        List<GetOpenQuotesForAccount.Response> res =
            GetOpenQuotesForAccount.getQuotes(new List<GetOpenQuotesForAccount.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res.size(), 'One response expected');
        System.assertEquals(1, res[0].quoteCount, 'Should find the one open quote');
        System.assert(res[0].quoteSummary.contains('open quote'), 'Summary should mention quotes');
        System.assertEquals(1, res[0].quotes.size(), 'Quote records should be returned');
    }

    @isTest
    static void noQuotesFound() {
        Account a = new Account(Name = 'Empty Account');
        insert a;

        GetOpenQuotesForAccount.Request req = new GetOpenQuotesForAccount.Request();
        req.accountId = a.Id;

        Test.startTest();
        List<GetOpenQuotesForAccount.Response> res =
            GetOpenQuotesForAccount.getQuotes(new List<GetOpenQuotesForAccount.Request>{ req });
        Test.stopTest();

        System.assertEquals(0, res[0].quoteCount, 'No quotes expected');
        System.assert(res[0].quotes.isEmpty(), 'Quote list should be empty');
    }

    @isTest
    static void blankAccountId() {
        GetOpenQuotesForAccount.Request req = new GetOpenQuotesForAccount.Request();
        req.accountId = '';

        List<GetOpenQuotesForAccount.Response> res =
            GetOpenQuotesForAccount.getQuotes(new List<GetOpenQuotesForAccount.Request>{ req });

        System.assertEquals(0, res[0].quoteCount, 'Blank account id returns 0');
        System.assert(res[0].quoteSummary.contains('No Account ID'), 'Should warn about missing id');
    }
}
