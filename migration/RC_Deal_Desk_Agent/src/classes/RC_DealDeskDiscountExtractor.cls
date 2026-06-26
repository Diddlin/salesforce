global with sharing class RC_DealDeskDiscountExtractor {

    // ---------- INPUT FROM FLOW ----------
    global class Request {
        @InvocableVariable(
            label='Full DealDesk JSON'
            description='The trimmed JSON payload from the prompt (no human text, just the JSON object).'
        )
        public String fullJson;

        @InvocableVariable(
            label='Quote Id'
            description='Id of the Quote related to this JSON.'
        )
        public Id quoteId;
    }

    // ---------- OUTPUT BACK TO FLOW ----------
    global class Recommendation {
        @InvocableVariable(label='Quote Line Item Id')
        public String quoteLineItemId;

        @InvocableVariable(label='Recommended Discount')
        public Decimal recommendedDiscount;

        @InvocableVariable(label='Current Discount')
        public Decimal currentDiscount;

        @InvocableVariable(label='Category (ARR / MRR / OneTime)')
        public String category;
    }

    @InvocableMethod(
        label='Deal Desk – Extract & Persist Discount Recommendations'
        description='Parses DealDesk JSON, creates DealDesk Recommendation records, and returns a flat list of discount recommendations.'
    )
    global static List<Recommendation> extract(List<Request> requests) {
        List<Recommendation> allResults = new List<Recommendation>();

        if (requests == null || requests.isEmpty()) {
            return allResults;
        }

        // We’ll also collect records to insert
        List<RC_DealDesk_Recommendation__c> toInsert = new List<RC_DealDesk_Recommendation__c>();

        for (Request req : requests) {
            if (String.isBlank(req.fullJson)) {
                continue;
            }

            try {
                String jsonText = req.fullJson.trim();

                // Defensive: if something snuck in before the JSON, strip up to first "{"
                Integer bracePos = jsonText.indexOf('{');
                if (bracePos > 0) {
                    jsonText = jsonText.substring(bracePos);
                }

                // Normalize non-breaking spaces that can break JSON parsing
                jsonText = jsonText.replaceAll('[\\u00A0\\u2007\\u202F]', ' ');

                // Try standard parse
                Object rootObj = JSON.deserializeUntyped(jsonText);

                // If it looks like an OpenAI body, unwrap it
                rootObj = tryUnwrapLLMBody(rootObj);

                if (!(rootObj instanceof Map<String, Object>)) {
                    continue;
                }

                Map<String, Object> root = (Map<String, Object>) rootObj;

                // Parse recommendations for this request
                List<Recommendation> recsForThisRequest =
                    new List<Recommendation>();

                List<String> categories = new List<String>{ 'ARR', 'MRR', 'OneTime' };
                for (String cat : categories) {
                    addCategoryLines(root, cat, recsForThisRequest);
                }

                // Convert those into RC_DealDesk_Recommendation__c records
                for (Recommendation r : recsForThisRequest) {
                    RC_DealDesk_Recommendation__c rec = new RC_DealDesk_Recommendation__c();
                    rec.RC_Quote__c = req.quoteId;
                    rec.RC_QuoteLineItemId__c = r.quoteLineItemId;
                    rec.RC_RecommendedDiscount__c = r.recommendedDiscount;
                    rec.RC_CurrentDiscount__c = r.currentDiscount;
                    rec.RC_Category__c = r.category;
                    rec.RC_Applied__c = false;
                    toInsert.add(rec);
                }

                // Add to overall list returned to Flow
                allResults.addAll(recsForThisRequest);

            } catch (Exception e) {
                System.debug('RC_DealDeskDiscountExtractor error: ' + e.getMessage());
                // Don’t throw – we want Flow to continue even if this fails
            }
        }

        // Actually insert the DealDesk Recommendation records
        if (!toInsert.isEmpty()) {
            try {
                insert toInsert;
            } catch (Exception e) {
                System.debug('Error inserting RC_DealDesk_Recommendation__c records: ' + e.getMessage());
                // Swallow so Flow doesn’t blow up
            }
        }

        // Flow will see one row per recommendation in the Outputs section
        return allResults;
    }

    // ---------- HELPERS ----------

    // Reads ARR/MRR/OneTime node and pushes its lines[] as Recommendation rows
    private static void addCategoryLines(
        Map<String, Object> root,
        String categoryKey,
        List<Recommendation> results
    ) {
        if (root == null || !root.containsKey(categoryKey)) {
            return;
        }

        Object catObj = root.get(categoryKey);
        if (!(catObj instanceof Map<String, Object>)) {
            // null or not an object (e.g., MRR:null) -> nothing to do
            return;
        }

        Map<String, Object> cat = (Map<String, Object>) catObj;

        // support both "lines" / "Lines" and legacy "recommendedDiscount"
        Object linesObj;
        if (cat.containsKey('lines')) {
            linesObj = cat.get('lines');
        } else if (cat.containsKey('Lines')) {
            linesObj = cat.get('Lines');
        } else if (cat.containsKey('recommendedDiscount')) {
            linesObj = cat.get('recommendedDiscount');
        } else {
            return;
        }

        if (!(linesObj instanceof List<Object>)) {
            return;
        }

        List<Object> lines = (List<Object>) linesObj;

        for (Object o : lines) {
            if (!(o instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> line = (Map<String, Object>) o;

            if (!line.containsKey('QuoteLineItemId') || !line.containsKey('RecommendedDiscount')) {
                continue;
            }

            String qliId = String.valueOf(line.get('QuoteLineItemId'));
            if (String.isBlank(qliId)) {
                continue;
            }

            Decimal recDisc;
            try {
                Object rd = line.get('RecommendedDiscount');
                if (rd == null) continue;
                recDisc = Decimal.valueOf(String.valueOf(rd));
            } catch (Exception e) {
                continue;
            }

            Decimal curDisc = null;
            if (line.containsKey('CurrentDiscount')) {
                try {
                    curDisc = Decimal.valueOf(String.valueOf(line.get('CurrentDiscount')));
                } catch (Exception ignore) {
                    curDisc = null;
                }
            }

            Recommendation r = new Recommendation();
            r.quoteLineItemId = qliId;
            r.recommendedDiscount = recDisc;
            r.currentDiscount = curDisc;
            r.category = categoryKey;
            results.add(r);
        }
    }

    // If the JSON was a full LLM body, unwrap choices[0].message.content / text
    private static Object tryUnwrapLLMBody(Object rootObj) {
        try {
            if (rootObj instanceof Map<String, Object>) {
                Map<String, Object> root = (Map<String, Object>) rootObj;

                if (root.containsKey('choices')) {
                    List<Object> choices = (List<Object>) root.get('choices');
                    if (!choices.isEmpty()) {
                        Object c0 = choices[0];
                        if (c0 instanceof Map<String, Object>) {
                            Map<String, Object> choice0 = (Map<String, Object>) c0;

                            if (choice0.containsKey('message')) {
                                Object msg = choice0.get('message');
                                if (msg instanceof Map<String, Object>) {
                                    Map<String, Object> m = (Map<String, Object>) msg;
                                    if (m.containsKey('content')) {
                                        String content = String.valueOf(m.get('content'));
                                        return JSON.deserializeUntyped(content);
                                    }
                                }
                            }

                            if (choice0.containsKey('text')) {
                                String text = String.valueOf(choice0.get('text'));
                                return JSON.deserializeUntyped(text);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            // ignore and just use original rootObj
        }
        return rootObj;
    }
}