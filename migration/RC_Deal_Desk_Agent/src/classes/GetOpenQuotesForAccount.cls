/**
 * Invocable Apex for the Get Open Quotes For Account Agentforce action.
 * Looks up open quotes via three paths:
 *   1. Directly on the account (Quote.AccountId)
 *   2. Via opportunities on the account (Quote.Opportunity.AccountId)
 *   3. Via contracts on the account (Quote linked to Opportunity linked to Contract)
 *
 * Returns both a text summary AND the Quote record collection so Agentforce
 * can render clickable record cards in the response.
 */
public class GetOpenQuotesForAccount {

    public class Request {
        @InvocableVariable(required=true label='Account ID' description='The Salesforce Account ID to look up quotes for.')
        public String accountId;
    }

    public class Response {
        @InvocableVariable(label='Quote Summary' description='Formatted summary of all open quotes found for this account.')
        public String quoteSummary;

        @InvocableVariable(label='Quote Count' description='Total number of open quotes found.')
        public Integer quoteCount;

        @InvocableVariable(label='Quotes' description='Collection of open Quote records — rendered as clickable cards by Agentforce.')
        public List<Quote> quotes;
    }

    @InvocableMethod(
        label='Get Open Quotes For Account'
        description='Returns all open quotes associated with an account — directly on the account, via its opportunities, or via its contracts. Returns clickable Quote records and a summary.'
        category='Quote'
    )
    public static List<Response> getQuotes(List<Request> requests) {
        List<Response> responses = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();

            if (String.isBlank(req.accountId)) {
                res.quoteSummary = 'No Account ID was provided.';
                res.quoteCount = 0;
                res.quotes = new List<Quote>();
                responses.add(res);
                continue;
            }

            String accId = req.accountId;
            Set<Id> quoteIds = new Set<Id>();
            List<Quote> allQuotes = new List<Quote>();

            // Path 1 & 2: Quotes directly on account OR via opportunities on account
            List<Quote> q1 = [
                SELECT Id, Name, Status, TotalPrice, ExpirationDate,
                       OpportunityId, Opportunity.Name, AccountId, Account.Name
                FROM Quote
                WHERE (AccountId = :accId OR Opportunity.AccountId = :accId)
                AND Status != 'Closed'
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
            for (Quote q : q1) {
                if (!quoteIds.contains(q.Id)) {
                    quoteIds.add(q.Id);
                    allQuotes.add(q);
                }
            }

            // Path 3: Quotes via Contracts on the account
            List<Contract> contracts = [
                SELECT Id FROM Contract WHERE AccountId = :accId LIMIT 50
            ];
            Set<Id> contractIds = new Set<Id>();
            for (Contract c : contracts) contractIds.add(c.Id);

            if (!contractIds.isEmpty()) {
                List<Quote> q3 = [
                    SELECT Id, Name, Status, TotalPrice, ExpirationDate,
                           OpportunityId, Opportunity.Name, AccountId, Account.Name
                    FROM Quote
                    WHERE Opportunity.ContractId IN :contractIds
                    AND Status != 'Closed'
                    ORDER BY CreatedDate DESC
                    LIMIT 100
                ];
                for (Quote q : q3) {
                    if (!quoteIds.contains(q.Id)) {
                        quoteIds.add(q.Id);
                        allQuotes.add(q);
                    }
                }
            }

            // Build response
            if (allQuotes.isEmpty()) {
                res.quoteSummary = 'No open quotes found for this account — checked directly on the account, via its opportunities, and via its contracts.';
                res.quoteCount = 0;
                res.quotes = new List<Quote>();
            } else {
                String baseUrl = URL.getOrgDomainUrl().toExternalForm();
                String summary = 'Found ' + allQuotes.size() + ' open quote(s) for this account:\n\n';
                for (Quote q : allQuotes) {
                    String recordUrl = baseUrl + '/lightning/r/Quote/' + q.Id + '/view';
                    summary += '• [' + q.Name + '](' + recordUrl + ')';
                    summary += ' | Status: ' + q.Status;
                    if (q.TotalPrice != null) {
                        summary += ' | Total: $' + q.TotalPrice.format();
                    }
                    if (q.Opportunity != null && String.isNotBlank(q.Opportunity.Name)) {
                        summary += ' | Opportunity: ' + q.Opportunity.Name;
                    }
                    if (q.ExpirationDate != null) {
                        summary += ' | Expires: ' + q.ExpirationDate.format();
                    }
                    summary += '\n';
                }
                res.quoteSummary = summary;
                res.quoteCount = allQuotes.size();
                res.quotes = allQuotes;
            }

            responses.add(res);
        }

        return responses;
    }
}