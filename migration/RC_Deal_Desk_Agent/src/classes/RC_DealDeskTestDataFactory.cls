/**
 * Test-only data factory for the RC Deal Desk Agent components.
 * Builds a standard Quote + QuoteLineItem graph (Account -> Opportunity ->
 * Pricebook/Product -> Quote -> QuoteLineItem) usable by the Deal Desk tests.
 */
@isTest
public class RC_DealDeskTestDataFactory {

    public class QuoteContext {
        public Account account;
        public Opportunity opportunity;
        public Product2 product;
        public PricebookEntry pricebookEntry;
        public Quote quote;
        public QuoteLineItem quoteLineItem;
    }

    public static QuoteContext createQuoteWithLine() {
        QuoteContext ctx = new QuoteContext();

        ctx.account = new Account(Name = 'DealDesk Test Account');
        insert ctx.account;

        ctx.opportunity = new Opportunity(
            Name = 'DealDesk Test Opp',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = ctx.account.Id
        );
        insert ctx.opportunity;

        ctx.product = new Product2(Name = 'DealDesk Test Product', IsActive = true);
        insert ctx.product;

        Id stdPricebookId = Test.getStandardPricebookId();
        ctx.pricebookEntry = new PricebookEntry(
            Pricebook2Id = stdPricebookId,
            Product2Id = ctx.product.Id,
            UnitPrice = 1000,
            IsActive = true
        );
        insert ctx.pricebookEntry;

        ctx.quote = new Quote(
            Name = 'DealDesk Test Quote',
            OpportunityId = ctx.opportunity.Id,
            Pricebook2Id = stdPricebookId
        );
        insert ctx.quote;

        ctx.quoteLineItem = new QuoteLineItem(
            QuoteId = ctx.quote.Id,
            PricebookEntryId = ctx.pricebookEntry.Id,
            Quantity = 1,
            UnitPrice = 1000,
            Discount = 10
        );
        insert ctx.quoteLineItem;

        return ctx;
    }
}
