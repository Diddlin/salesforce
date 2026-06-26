global with sharing class RC_DealDeskDiscountApplier {

    // ---------- INPUT FROM FLOW ----------
    global class Request {
        @InvocableVariable(label='Quote Id' description='Id of the Quote to apply discounts to')
        public Id quoteId;
    }

    // ---------- OUTPUT BACK TO FLOW ----------
    global class Result {
        @InvocableVariable(label='Total Lines Found In JSON')
        public Integer totalLines;

        @InvocableVariable(label='Lines Updated Successfully')
        public Integer updatedLines;

        @InvocableVariable(label='Lines Failed')
        public Integer failedLines;

        @InvocableVariable(label='Human Summary Message')
        public String summaryMessage;

        // JSON array string of failure details: [{ "QuoteLineItemId":"...", "reason":"..." }, ...]
        @InvocableVariable(label='Failure Details (JSON)')
        public String failureDetailsJson;
    }

    @InvocableMethod(
        label='DealDesk - Apply Discounts'
        description='Applies recommended discounts from Quote.RC_Quote_DealDeskFullJson__c to matching QuoteLineItem records. Best-effort; returns summary.'
    )
    global static List<Result> apply(List<Request> requests) {
        List<Result> outs = new List<Result>();
        if (requests == null || requests.isEmpty()) {
            return outs;
        }

        for (Request req : requests) {
            Result res = new Result();
            res.totalLines = 0;
            res.updatedLines = 0;
            res.failedLines = 0;
            res.summaryMessage = '';
            res.failureDetailsJson = '[]';

            if (req == null || req.quoteId == null) {
                res.summaryMessage = 'No quoteId provided.';
                outs.add(res);
                continue;
            }

            try {
                // Query the Quote to get the trimmed JSON
                Quote q = [
                    SELECT Id, RC_Quote_DealDeskFullJson__c
                    FROM Quote
                    WHERE Id = :req.quoteId
                    LIMIT 1
                ];

                if (q == null || String.isBlank(q.RC_Quote_DealDeskFullJson__c)) {
                    res.summaryMessage = 'No DealDesk JSON found on the quote.';
                    outs.add(res);
                    continue;
                }

                // Normalize string
                String rawJson = q.RC_Quote_DealDeskFullJson__c.trim();
                Integer bracePos = rawJson.indexOf('{');
                if (bracePos > 0) {
                    rawJson = rawJson.substring(bracePos);
                }
                rawJson = rawJson.replaceAll('[\\u00A0\\u2007\\u202F]', ' ');

                // Attempt parse
                Object rootObj;
                try {
                    rootObj = JSON.deserializeUntyped(rawJson);
                } catch (Exception ex) {
                    res.summaryMessage = 'Failed to parse DealDesk JSON on the quote: ' + ex.getMessage();
                    outs.add(res);
                    continue;
                }

                // If it looks like an LLM envelope, unwrap
                rootObj = tryUnwrapLLMBody(rootObj);

                if (!(rootObj instanceof Map<String, Object>)) {
                    res.summaryMessage = 'Parsed DealDesk JSON root is not an object.';
                    outs.add(res);
                    continue;
                }

                Map<String, Object> root = (Map<String, Object>) rootObj;

                // ------------------------------------------------------------
                // Flatten recommended lines from ARR / MRR / OneTime
                // ------------------------------------------------------------
                List<Map<String, Object>> flattened = new List<Map<String, Object>>();
                List<String> categories = new List<String>{ 'ARR', 'MRR', 'OneTime' };

                for (String cat : categories) {
                    if (!root.containsKey(cat)) continue;
                    Object catObj = root.get(cat);
                    if (!(catObj instanceof Map<String, Object>)) continue;

                    Map<String, Object> catMap = (Map<String, Object>) catObj;

                    // We now ONLY care about the per-line recommendedDiscount array
                    Object linesObj = null;
                    if (catMap.containsKey('recommendedDiscount')) {
                        linesObj = catMap.get('recommendedDiscount');
                    } else if (catMap.containsKey('RecommendedDiscount')) {
                        linesObj = catMap.get('RecommendedDiscount');
                    }

                    if (!(linesObj instanceof List<Object>)) continue;
                    List<Object> lines = (List<Object>) linesObj;

                    for (Object o : lines) {
                        if (!(o instanceof Map<String, Object>)) continue;
                        Map<String, Object> line = (Map<String, Object>) o;

                        // Expect shape:
                        // { "QuoteLineItemId": "...", "RecommendedDiscount": 25, ... }
                        if (!line.containsKey('QuoteLineItemId')) continue;
                        if (!line.containsKey('RecommendedDiscount')) continue;

                        Map<String, Object> entry = new Map<String, Object>();
                        entry.put('QuoteLineItemId', String.valueOf(line.get('QuoteLineItemId')));
                        entry.put('RecommendedDiscount', line.get('RecommendedDiscount'));
                        entry.put('CurrentDiscount', line.containsKey('CurrentDiscount') ? line.get('CurrentDiscount') : null);
                        entry.put('Category', cat);

                        // ProductName, if LLM sent it
                        if (line.containsKey('ProductName')) {
                            entry.put('ProductName', line.get('ProductName'));
                        }

                        if (line.containsKey('Reason')) {
                            entry.put('Reason', line.get('Reason'));
                        }
                        if (line.containsKey('AboveThreshold')) {
                            entry.put('AboveThreshold', line.get('AboveThreshold'));
                        }

                        flattened.add(entry);
                    }
                }

                res.totalLines = flattened.size();
                if (res.totalLines == 0) {
                    res.summaryMessage = 'No recommended discounts found in the DealDesk JSON.';
                    outs.add(res);
                    continue;
                }

                // ------------------------------------------------------------
                // Build QLI Id set from flattened entries
                // ------------------------------------------------------------
                Set<Id> qliIds = new Set<Id>();
                for (Map<String, Object> e : flattened) {
                    String idStr = (String) e.get('QuoteLineItemId');
                    if (String.isNotBlank(idStr)) {
                        try {
                            qliIds.add(Id.valueOf(idStr));
                        } catch (Exception ex) {
                            // invalid Id – will be captured as a failure when we loop
                        }
                    }
                }

                // ------------------------------------------------------------
                // Query existing QLIs
                // ------------------------------------------------------------
                Map<Id, QuoteLineItem> qliMap = new Map<Id, QuoteLineItem>();
                if (!qliIds.isEmpty()) {
                    for (QuoteLineItem qli : [
                        SELECT Id, QuoteId, Discount, RelatedQuoteLineItemId
                        FROM QuoteLineItem
                        WHERE Id IN :qliIds
                    ]) {
                        qliMap.put(qli.Id, qli);
                    }
                }

                // ------------------------------------------------------------
                // Query existing RC_DealDesk_Recommendation__c (one per QLI per Quote)
                // ------------------------------------------------------------
                Map<String, RC_DealDesk_Recommendation__c> existingRecsByQli =
                    new Map<String, RC_DealDesk_Recommendation__c>();

                for (RC_DealDesk_Recommendation__c rec : [
                    SELECT Id, RC_Quote__c, RC_QuoteLineItemId__c, RC_ProductName__c,
                           RC_CurrentDiscount__c, RC_RecommendedDiscount__c,
                           RC_Category__c, RC_Applied__c, RC_Source__c
                    FROM RC_DealDesk_Recommendation__c
                    WHERE RC_Quote__c = :req.quoteId
                ]) {
                    if (rec.RC_QuoteLineItemId__c != null) {
                        existingRecsByQli.put(rec.RC_QuoteLineItemId__c, rec);
                    }
                }

                // ------------------------------------------------------------
                // Prepare updates and audit records (ALL categories)
                // ------------------------------------------------------------
                List<QuoteLineItem> toUpdate = new List<QuoteLineItem>();
                List<RC_DealDesk_Recommendation__c> auditsToUpsert = new List<RC_DealDesk_Recommendation__c>();
                List<Map<String, String>> failures = new List<Map<String, String>>();

                for (Map<String, Object> e : flattened) {
                    String category = (String) e.get('Category');

                    // *** CHANGE: previously we skipped non-ARR here.
                    // Now we apply recommendations for ARR, MRR, and OneTime. ***

                    String qliIdStr = (String) e.get('QuoteLineItemId');
                    Object rdObj    = e.get('RecommendedDiscount');

                    if (String.isBlank(qliIdStr) || rdObj == null) {
                        failures.add(new Map<String, String>{
                            'QuoteLineItemId' => qliIdStr,
                            'reason'          => 'Missing QLI id or RecommendedDiscount.'
                        });
                        continue;
                    }

                    Decimal recDisc;
                    try {
                        if (rdObj instanceof Decimal) {
                            recDisc = (Decimal) rdObj;
                        } else if (rdObj instanceof Integer) {
                            recDisc = Decimal.valueOf((Integer) rdObj);
                        } else {
                            recDisc = Decimal.valueOf(String.valueOf(rdObj));
                        }
                    } catch (Exception ex) {
                        failures.add(new Map<String, String>{
                            'QuoteLineItemId' => qliIdStr,
                            'reason'          => 'RecommendedDiscount is not numeric.'
                        });
                        continue;
                    }

                    Id qliId;
                    try {
                        qliId = Id.valueOf(qliIdStr);
                    } catch (Exception ex) {
                        failures.add(new Map<String, String>{
                            'QuoteLineItemId' => qliIdStr,
                            'reason'          => 'Invalid QuoteLineItem Id format.'
                        });
                        continue;
                    }

                    if (!qliMap.containsKey(qliId)) {
                        failures.add(new Map<String, String>{
                            'QuoteLineItemId' => qliIdStr,
                            'reason'          => 'QuoteLineItem not found in org (or not accessible).'
                        });
                        continue;
                    }

                    QuoteLineItem existingQLI = qliMap.get(qliId);

                    // Apply discount
                    existingQLI.Discount = recDisc;
                    toUpdate.add(existingQLI);

                    // --------------------------------------------------------
                    // Build / update audit record (de-dupe by QuoteLineItemId)
                    // --------------------------------------------------------
                    try {
                        RC_DealDesk_Recommendation__c r;
                        if (existingRecsByQli.containsKey(qliIdStr)) {
                            // update existing record
                            r = existingRecsByQli.get(qliIdStr);
                        } else {
                            // create new record
                            r = new RC_DealDesk_Recommendation__c();
                            r.RC_Quote__c = req.quoteId;
                            r.RC_QuoteLineItemId__c = qliIdStr;
                            r.RC_Source__c = 'RC_DealDesk';
                        }

                        r.RC_RecommendedDiscount__c = recDisc;
                        r.RC_Category__c = category;
                        r.RC_Applied__c  = true;

                        // Product Name from JSON (if present)
                        if (e.containsKey('ProductName') && e.get('ProductName') != null) {
                            r.RC_ProductName__c = String.valueOf(e.get('ProductName'));
                        }

                        // Current Discount from JSON (if present & parseable)
                        if (e.containsKey('CurrentDiscount') && e.get('CurrentDiscount') != null) {
                            try {
                                r.RC_CurrentDiscount__c =
                                    Decimal.valueOf(String.valueOf(e.get('CurrentDiscount')));
                            } catch (Exception ignoreCd) {
                                // swallow parse errors, keep going
                            }
                        }

                        auditsToUpsert.add(r);
                    } catch (Exception ignoreAudit) {
                        // do not block the main flow
                    }
                }

                // ------------------------------------------------------------
                // Bulk update QLIs
                // ------------------------------------------------------------
                Integer updated = 0;
                if (!toUpdate.isEmpty()) {
                    try {
                        update toUpdate;
                        updated = toUpdate.size();
                    } catch (DmlException dmle) {
                        // fallback to row-by-row
                        for (QuoteLineItem up : toUpdate) {
                            try {
                                update up;
                                updated++;
                            } catch (Exception rowEx) {
                                failures.add(new Map<String, String>{
                                    'QuoteLineItemId' => String.valueOf(up.Id),
                                    'reason'          => 'DML error: ' + rowEx.getMessage()
                                });
                            }
                        }
                    }
                }
                res.updatedLines = updated;

                // ------------------------------------------------------------
                // Upsert audit records
                // ------------------------------------------------------------
                if (!auditsToUpsert.isEmpty()) {
                    try {
                        upsert auditsToUpsert;
                    } catch (Exception ignoreAuditDml) {
                        // audit failure shouldn't block discount application
                    }
                }

                // ------------------------------------------------------------
                // Build failure details + summary
                // ------------------------------------------------------------
                res.failedLines = failures.size();
                res.failureDetailsJson = failures.isEmpty()
                    ? '[]'
                    : JSON.serialize(failures);

                res.summaryMessage =
                    'Applied recommended discounts to ' + String.valueOf(res.updatedLines) +
                    ' of ' + String.valueOf(res.totalLines) + ' recommended line(s).';
                if (res.failedLines > 0) {
                    res.summaryMessage +=
                        ' ' + String.valueOf(res.failedLines) + ' line(s) failed or were skipped.';
                }

            } catch (Exception e) {
                res.summaryMessage = 'Unexpected error applying discounts: ' + e.getMessage();
            }

            outs.add(res);
        }

        return outs;
    }

    // ------------------------------------------------------------
    // Helper: unwrap an LLM response envelope if present
    // ------------------------------------------------------------
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

                            // OpenAI-style: choices[0].message.content
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

                            // Legacy-style: choices[0].text
                            if (choice0.containsKey('text')) {
                                String text = String.valueOf(choice0.get('text'));
                                return JSON.deserializeUntyped(text);
                            }
                        }
                    }
                }
            }
        } catch (Exception e) {
            // ignore and use original rootObj
        }
        return rootObj;
    }
}