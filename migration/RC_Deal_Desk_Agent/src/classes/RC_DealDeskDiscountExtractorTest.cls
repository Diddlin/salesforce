@isTest
private class RC_DealDeskDiscountExtractorTest {

    @isTest
    static void extractsAndPersistsRecommendations() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();
        String qliId = ctx.quoteLineItem.Id;

        String json =
            '{ "ARR": { "lines": [ { "QuoteLineItemId": "' + qliId + '",' +
            '  "RecommendedDiscount": 25, "CurrentDiscount": 10 } ] },' +
            '  "MRR": null,' +
            '  "OneTime": { "recommendedDiscount": [ { "QuoteLineItemId": "' + qliId + '", "RecommendedDiscount": 5 } ] } }';

        RC_DealDeskDiscountExtractor.Request req = new RC_DealDeskDiscountExtractor.Request();
        req.fullJson = json;
        req.quoteId = ctx.quote.Id;

        Test.startTest();
        List<RC_DealDeskDiscountExtractor.Recommendation> recs =
            RC_DealDeskDiscountExtractor.extract(new List<RC_DealDeskDiscountExtractor.Request>{ req });
        Test.stopTest();

        System.assertEquals(2, recs.size(), 'ARR + OneTime lines extracted');
        List<RC_DealDesk_Recommendation__c> persisted =
            [SELECT Id, RC_Category__c, RC_RecommendedDiscount__c FROM RC_DealDesk_Recommendation__c WHERE RC_Quote__c = :ctx.quote.Id];
        System.assertEquals(2, persisted.size(), 'Recommendation records persisted');
    }

    @isTest
    static void unwrapsLlmEnvelope() {
        RC_DealDeskTestDataFactory.QuoteContext ctx =
            RC_DealDeskTestDataFactory.createQuoteWithLine();
        String qliId = ctx.quoteLineItem.Id;

        String innerJson =
            '{ "ARR": { "lines": [ { "QuoteLineItemId": "' + qliId + '", "RecommendedDiscount": 30 } ] } }';
        // Escape the inner JSON as a string value inside an OpenAI-style envelope
        String envelope =
            '{ "choices": [ { "message": { "content": ' + JSON.serialize(innerJson) + ' } } ] }';

        RC_DealDeskDiscountExtractor.Request req = new RC_DealDeskDiscountExtractor.Request();
        req.fullJson = envelope;
        req.quoteId = ctx.quote.Id;

        List<RC_DealDeskDiscountExtractor.Recommendation> recs =
            RC_DealDeskDiscountExtractor.extract(new List<RC_DealDeskDiscountExtractor.Request>{ req });

        System.assertEquals(1, recs.size(), 'Envelope unwrapped and line extracted');
    }

    @isTest
    static void handlesBlankAndEmpty() {
        RC_DealDeskDiscountExtractor.Request blank = new RC_DealDeskDiscountExtractor.Request();
        blank.fullJson = '';
        List<RC_DealDeskDiscountExtractor.Recommendation> recs =
            RC_DealDeskDiscountExtractor.extract(new List<RC_DealDeskDiscountExtractor.Request>{ blank });
        System.assert(recs.isEmpty(), 'Blank json yields nothing');

        System.assert(
            RC_DealDeskDiscountExtractor.extract(new List<RC_DealDeskDiscountExtractor.Request>()).isEmpty(),
            'Empty request list yields nothing'
        );
    }
}
