/**
 * RC_DealDeskJsonTrimmer
 *
 * Invocable helper called from Flow A.
 * It takes the FULL raw response from the Prompt Template (human text + JSON),
 * extracts the JSON between JSON_PAYLOAD_START and JSON_PAYLOAD_END,
 * parses it, and returns:
 *  - cleanJson             : the JSON object as a string (for Flow B / extractor)
 *  - arrCommentary         : synthesized ARR commentary (or ARR.commentary if present)
 *  - mrrCommentary         : synthesized MRR commentary (or MRR.commentary if present)
 *  - oneTimeCommentary     : synthesized One Time commentary (or OneTime.commentary if present)
 *  - commissionCommentary  : Commission.commentary (if present)
 *  - summaryText           : SummaryText from the JSON
 */
public with sharing class RC_DealDeskJsonTrimmer {

    // -------- INPUT WRAPPER --------
    public class Request {
        @InvocableVariable(required=true)
        public String fullResponse; // entire Prompt Template output
    }

    // -------- OUTPUT WRAPPER --------
    public class Result {
        @InvocableVariable
        public String cleanJson;

        @InvocableVariable
        public String arrCommentary;

        @InvocableVariable
        public String mrrCommentary;

        @InvocableVariable
        public String oneTimeCommentary;

        @InvocableVariable
        public String commissionCommentary;

        @InvocableVariable
        public String summaryText;
    }

    @InvocableMethod(
        label='Deal Desk – Trim & Parse JSON'
        description='Extracts JSON between JSON_PAYLOAD_START/END, parses, and returns commentaries and clean JSON.'
    )
    public static List<Result> trim(List<Request> requests) {
        List<Result> out = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            return out;
        }

        for (Request req : requests) {
            Result r = new Result();

            if (String.isBlank(req.fullResponse)) {
                r.cleanJson = '{}';
                r.arrCommentary = '';
                r.mrrCommentary = '';
                r.oneTimeCommentary = '';
                r.commissionCommentary = '';
                r.summaryText = '';
                out.add(r);
                continue;
            }

            try {
                String raw = req.fullResponse;

                // Find JSON_PAYLOAD_START and JSON_PAYLOAD_END
                String startMarker = 'JSON_PAYLOAD_START';
                String endMarker   = 'JSON_PAYLOAD_END';

                Integer startIdx = raw.indexOf(startMarker);
                Integer endIdx   = raw.indexOf(endMarker);

                if (startIdx == -1 || endIdx == -1) {
                    // Markers missing – just try to parse the whole thing as JSON
                    String trimmedWhole = raw.trim();

                    // Normalize weird unicode spaces in the entire payload
                    trimmedWhole = trimmedWhole.replaceAll('[\\u00A0\\u2007\\u202F]', ' ');

                    r.cleanJson = trimmedWhole;

                    Map<String, Object> root =
                        (Map<String, Object>) JSON.deserializeUntyped(trimmedWhole);
                    populateFromRoot(root, r);
                    out.add(r);
                    continue;
                }

                // Extract content between markers
                Integer jsonStart = startIdx + startMarker.length();
                String jsonChunk = raw.substring(jsonStart, endIdx);

                // Normalize any weird unicode spaces to regular spaces
                jsonChunk = jsonChunk.replaceAll('[\\u00A0\\u2007\\u202F]', ' ');

                // Trim normal whitespace
                jsonChunk = jsonChunk.trim();

                // Ensure we start at the first '{'
                Integer bracePos = jsonChunk.indexOf('{');
                if (bracePos > 0) {
                    jsonChunk = jsonChunk.substring(bracePos);
                }

                r.cleanJson = jsonChunk;

                // Parse JSON
                Map<String, Object> root =
                    (Map<String, Object>) JSON.deserializeUntyped(jsonChunk);
                populateFromRoot(root, r);
            } catch (Exception e) {
                // On any error, return minimal info
                r.cleanJson = '{}';
                r.arrCommentary = '';
                r.mrrCommentary = '';
                r.oneTimeCommentary = '';
                r.commissionCommentary =
                    'Error parsing JSON in RC_DealDeskJsonTrimmer: ' + e.getMessage();
                r.summaryText = '';
            }

            out.add(r);
        }

        return out;
    }

    // -------- Helper: safe averageDiscount parsing --------
    private static String normalizeAverageDiscount(Object avgObj) {
        if (avgObj == null) return null;

        try {
            // If numeric already
            if (avgObj instanceof Decimal) {
                Decimal d = (Decimal) avgObj;
                return d.setScale(1, RoundingMode.HALF_UP) + '%';
            }
            if (avgObj instanceof Integer) {
                Decimal d = Decimal.valueOf((Integer) avgObj);
                return d.setScale(1, RoundingMode.HALF_UP) + '%';
            }

            // String: may include a trailing '%'
            String s = String.valueOf(avgObj).trim();
            if (s.endsWith('%')) {
                s = s.substring(0, s.length() - 1).trim();
            }
            Decimal d = Decimal.valueOf(s);
            return d.setScale(1, RoundingMode.HALF_UP) + '%';
        } catch (Exception e) {
            // If we cannot parse, just return the raw string
            return String.valueOf(avgObj);
        }
    }

    private static Integer countRecommendedLines(Object recObj) {
        if (recObj instanceof List<Object>) {
            return ((List<Object>) recObj).size();
        }
        return 0;
    }

    // -------- Helper: synthesize per-category commentary --------
    private static String buildCategoryCommentary(
        String label,
        Map<String, Object> category
    ) {
        if (category == null) return '';

        // If the JSON already has a commentary field, prefer it.
        if (category.containsKey('commentary') && category.get('commentary') != null) {
            return String.valueOf(category.get('commentary'));
        }

        Object totalObj = category.containsKey('totalPrice') ? category.get('totalPrice') : null;
        Object avgObj   = category.containsKey('averageDiscount') ? category.get('averageDiscount') : null;
        Object recObj   = category.containsKey('recommendedDiscount') ? category.get('recommendedDiscount') : null;

        String avgText  = normalizeAverageDiscount(avgObj);
        Integer recCount = countRecommendedLines(recObj);

        String totalText;
        if (totalObj == null) {
            totalText = 'The ' + label + ' total amount was not provided.';
        } else {
            Decimal totalDec;
            try {
                if (totalObj instanceof Decimal) {
                    totalDec = (Decimal) totalObj;
                } else if (totalObj instanceof Integer) {
                    totalDec = Decimal.valueOf((Integer) totalObj);
                } else {
                    totalDec = Decimal.valueOf(String.valueOf(totalObj));
                }
                totalText = 'Total ' + label + ' is USD ' + totalDec.setScale(2, RoundingMode.HALF_UP) + '.';
            } catch (Exception e) {
                totalText = 'Total ' + label + ' is ' + String.valueOf(totalObj) + '.';
            }
        }

        String avgSentence = '';
        if (avgText != null) {
            avgSentence = ' The average discount is ' + avgText + '.';
        }

        String recSentence = '';
        if (recCount > 0) {
            recSentence =
                ' There are ' + String.valueOf(recCount) +
                ' recommended discount adjustment(s) in this category.';
        } else {
            recSentence =
                ' There are no recommended discount changes for this category.';
        }

        return totalText + avgSentence + recSentence;
    }

    // -------- Helper: pull fields from JSON object into Result --------
    private static void populateFromRoot(Map<String, Object> root, Result r) {
        if (root == null) return;

        // SummaryText
        if (root.containsKey('SummaryText') && root.get('SummaryText') != null) {
            r.summaryText = String.valueOf(root.get('SummaryText'));
        } else {
            r.summaryText = '';
        }

        // ARR
        if (root.containsKey('ARR')) {
            Object arrObj = root.get('ARR');
            if (arrObj instanceof Map<String, Object>) {
                Map<String, Object> arr = (Map<String, Object>) arrObj;
                r.arrCommentary = buildCategoryCommentary('ARR', arr);
            }
        } else {
            r.arrCommentary = '';
        }

        // MRR (may be null)
        if (root.containsKey('MRR')) {
            Object mrrObj = root.get('MRR');
            if (mrrObj instanceof Map<String, Object>) {
                Map<String, Object> mrr = (Map<String, Object>) mrrObj;
                r.mrrCommentary = buildCategoryCommentary('MRR', mrr);
            }
        } else {
            r.mrrCommentary = '';
        }

        // OneTime
        if (root.containsKey('OneTime')) {
            Object otObj = root.get('OneTime');
            if (otObj instanceof Map<String, Object>) {
                Map<String, Object> ot = (Map<String, Object>) otObj;
                r.oneTimeCommentary = buildCategoryCommentary('One Time', ot);
            }
        } else {
            r.oneTimeCommentary = '';
        }

        // Commission
        if (root.containsKey('Commission')) {
            Object commObj = root.get('Commission');
            if (commObj instanceof Map<String, Object>) {
                Map<String, Object> comm = (Map<String, Object>) commObj;
                if (comm != null && comm.containsKey('commentary') && comm.get('commentary') != null) {
                    r.commissionCommentary = String.valueOf(comm.get('commentary'));
                }
            }
        }
        if (r.commissionCommentary == null) {
            r.commissionCommentary = '';
        }
    }
}