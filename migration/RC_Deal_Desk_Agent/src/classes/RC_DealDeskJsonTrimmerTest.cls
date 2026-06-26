@isTest
private class RC_DealDeskJsonTrimmerTest {

    private static String payloadWithMarkers() {
        String json =
            '{ "SummaryText": "Looks good.",' +
            '  "ARR": { "totalPrice": 12000, "averageDiscount": "15%",' +
            '           "recommendedDiscount": [ { "QuoteLineItemId": "x", "RecommendedDiscount": 20 } ],' +
            '           "commentary": "ARR explicit commentary." },' +
            '  "MRR": { "totalPrice": 500, "averageDiscount": 10 },' +
            '  "OneTime": { "totalPrice": null },' +
            '  "Commission": { "commentary": "Commission note." } }';
        return 'Here is your analysis.\nJSON_PAYLOAD_START\n' + json + '\nJSON_PAYLOAD_END';
    }

    @isTest
    static void parsesPayloadWithMarkers() {
        RC_DealDeskJsonTrimmer.Request req = new RC_DealDeskJsonTrimmer.Request();
        req.fullResponse = payloadWithMarkers();

        List<RC_DealDeskJsonTrimmer.Result> res =
            RC_DealDeskJsonTrimmer.trim(new List<RC_DealDeskJsonTrimmer.Request>{ req });

        System.assertEquals(1, res.size());
        System.assertEquals('Looks good.', res[0].summaryText);
        System.assertEquals('ARR explicit commentary.', res[0].arrCommentary);
        System.assert(res[0].mrrCommentary.contains('MRR'), 'MRR commentary synthesized');
        System.assertEquals('Commission note.', res[0].commissionCommentary);
        System.assert(res[0].cleanJson.startsWith('{'), 'Clean json starts at brace');
    }

    @isTest
    static void parsesWholeWhenNoMarkers() {
        RC_DealDeskJsonTrimmer.Request req = new RC_DealDeskJsonTrimmer.Request();
        req.fullResponse = '{ "SummaryText": "No markers here.", "OneTime": { "totalPrice": 100, "averageDiscount": "5%" } }';

        List<RC_DealDeskJsonTrimmer.Result> res =
            RC_DealDeskJsonTrimmer.trim(new List<RC_DealDeskJsonTrimmer.Request>{ req });

        System.assertEquals('No markers here.', res[0].summaryText);
        System.assert(res[0].oneTimeCommentary.contains('One Time'), 'OneTime commentary synthesized');
    }

    @isTest
    static void handlesBlankAndMalformed() {
        RC_DealDeskJsonTrimmer.Request blank = new RC_DealDeskJsonTrimmer.Request();
        blank.fullResponse = '';

        RC_DealDeskJsonTrimmer.Request bad = new RC_DealDeskJsonTrimmer.Request();
        bad.fullResponse = 'JSON_PAYLOAD_START not-json JSON_PAYLOAD_END';

        List<RC_DealDeskJsonTrimmer.Result> res =
            RC_DealDeskJsonTrimmer.trim(new List<RC_DealDeskJsonTrimmer.Request>{ blank, bad });

        System.assertEquals(2, res.size());
        System.assertEquals('{}', res[0].cleanJson, 'Blank input yields empty object');
        System.assert(res[1].commissionCommentary.contains('Error parsing'), 'Malformed yields parse error note');
    }

    @isTest
    static void handlesEmptyList() {
        List<RC_DealDeskJsonTrimmer.Result> res =
            RC_DealDeskJsonTrimmer.trim(new List<RC_DealDeskJsonTrimmer.Request>());
        System.assert(res.isEmpty(), 'Empty input returns empty output');
    }
}
