@isTest
private class RC_DealDeskDiscountApplierTest {

    @isTest
    static void appliesDiscountsToLines() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();
        String qliId = ctx.quoteLineItem.Id;

        String json =
            '{ "ARR": { "recommendedDiscount": [ { "QuoteLineItemId": "' + qliId + '",' +
            '  "RecommendedDiscount": 25, "CurrentDiscount": 10, "ProductName": "DealDesk Test Product" } ] } }';
        ctx.quote.RC_Quote_DealDeskFullJson__c = json;
        update ctx.quote;

        RC_DealDeskDiscountApplier.Request req = new RC_DealDeskDiscountApplier.Request();
        req.quoteId = ctx.quote.Id;

        Test.startTest();
        List<RC_DealDeskDiscountApplier.Result> res =
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, res[0].totalLines, 'One line found in JSON');
        System.assertEquals(1, res[0].updatedLines, 'One line updated');
        System.assertEquals(0, res[0].failedLines, 'No failures');

        QuoteLineItem updated = [SELECT Discount FROM QuoteLineItem WHERE Id = :qliId];
        System.assertEquals(25, updated.Discount, 'Discount applied from JSON');

        List<RC_DealDesk_Recommendation__c> audits =
            [SELECT Id, RC_Applied__c FROM RC_DealDesk_Recommendation__c WHERE RC_Quote__c = :ctx.quote.Id];
        System.assertEquals(1, audits.size(), 'Audit record created');
        System.assertEquals(true, audits[0].RC_Applied__c, 'Audit marked applied');
    }

    @isTest
    static void noJsonOnQuote() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();

        RC_DealDeskDiscountApplier.Request req = new RC_DealDeskDiscountApplier.Request();
        req.quoteId = ctx.quote.Id;

        List<RC_DealDeskDiscountApplier.Result> res =
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>{ req });

        System.assertEquals(0, res[0].updatedLines, 'Nothing updated without JSON');
        System.assert(res[0].summaryMessage.contains('No DealDesk JSON'), 'Should report missing JSON');
    }

    @isTest
    static void malformedJsonOnQuote() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();
        ctx.quote.RC_Quote_DealDeskFullJson__c = 'this is not json at all';
        update ctx.quote;

        RC_DealDeskDiscountApplier.Request req = new RC_DealDeskDiscountApplier.Request();
        req.quoteId = ctx.quote.Id;

        List<RC_DealDeskDiscountApplier.Result> res =
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>{ req });

        System.assertEquals(0, res[0].updatedLines, 'Nothing updated for malformed JSON');
        System.assert(res[0].summaryMessage.contains('parse'), 'Should report a parse problem: ' + res[0].summaryMessage);
    }

    @isTest
    static void noRecommendedDiscounts() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();
        ctx.quote.RC_Quote_DealDeskFullJson__c =
            '{ "ARR": { "recommendedDiscount": [] }, "MRR": null }';
        update ctx.quote;

        RC_DealDeskDiscountApplier.Request req = new RC_DealDeskDiscountApplier.Request();
        req.quoteId = ctx.quote.Id;

        List<RC_DealDeskDiscountApplier.Result> res =
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>{ req });

        System.assertEquals(0, res[0].totalLines, 'No recommended lines present');
        System.assert(res[0].summaryMessage.contains('No recommended discounts'), 'Should report none found');
    }

    @isTest
    static void llmEnvelopeWithValidAndInvalidLines() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();
        String qliId = ctx.quoteLineItem.Id;

        String innerJson =
            '{ "ARR": { "recommendedDiscount": [' +
            '   { "QuoteLineItemId": "' + qliId + '", "RecommendedDiscount": 15 },' +
            '   { "QuoteLineItemId": "0QL000000000000AAA", "RecommendedDiscount": 40 } ] } }';
        String envelope =
            '{ "choices": [ { "message": { "content": ' + JSON.serialize(innerJson) + ' } } ] }';
        ctx.quote.RC_Quote_DealDeskFullJson__c = envelope;
        update ctx.quote;

        RC_DealDeskDiscountApplier.Request req = new RC_DealDeskDiscountApplier.Request();
        req.quoteId = ctx.quote.Id;

        Test.startTest();
        List<RC_DealDeskDiscountApplier.Result> res =
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>{ req });
        Test.stopTest();

        System.assertEquals(2, res[0].totalLines, 'Two lines parsed from envelope');
        System.assertEquals(1, res[0].updatedLines, 'Only the real QLI is updated');
        System.assertEquals(1, res[0].failedLines, 'The bogus QLI id is reported as a failure');
        System.assert(res[0].failureDetailsJson.contains('0QL'), 'Failure details include the bad id');
    }

    @isTest
    static void nullQuoteIdAndEmptyList() {
        RC_DealDeskDiscountApplier.Request req = new RC_DealDeskDiscountApplier.Request();
        req.quoteId = null;

        List<RC_DealDeskDiscountApplier.Result> res =
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>{ req });
        System.assert(res[0].summaryMessage.contains('No quoteId'), 'Should report missing quote id');

        System.assert(
            RC_DealDeskDiscountApplier.apply(new List<RC_DealDeskDiscountApplier.Request>()).isEmpty(),
            'Empty input returns empty output'
        );
    }
}
