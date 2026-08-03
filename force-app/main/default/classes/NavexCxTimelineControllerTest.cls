@IsTest
private class NavexCxTimelineControllerTest {
  private static final Date TODAY = Date.today();

  /**
   * The behaviour most of these tests are about is independent of the milestone filter, so they
   * go through this helper and leave milestonesOnly off. The tests that do exercise the filter
   * call getTimeline directly.
   */
  private static NavexCxTimelineController.Timeline timelineFor(
    Id recordId,
    Integer maxMilestones,
    Boolean includeFuture
  ) {
    return NavexCxTimelineController.getTimeline(
      recordId,
      maxMilestones,
      includeFuture,
      false
    );
  }

  // ---------------------------------------------------------------- fixtures

  private static Account newAccount() {
    return newAccount(null);
  }

  private static Account newAccount(Id ownerId) {
    Account account = new Account(Name = 'CX Timeline Test Account');
    if (ownerId != null) {
      account.OwnerId = ownerId;
    }
    insert account;
    return account;
  }

  private static Task newTask(
    Id accountId,
    String subject,
    String type,
    String status,
    Date activityDate
  ) {
    return new Task(
      WhatId = accountId,
      Subject = subject,
      Type = type,
      Status = status,
      ActivityDate = activityDate,
      Description = subject == null ? null : subject + ' description'
    );
  }

  private static Event newEvent(
    Id accountId,
    String subject,
    String type,
    Date activityDate
  ) {
    Datetime start = Datetime.newInstance(
      activityDate,
      Time.newInstance(9, 0, 0, 0)
    );
    return new Event(
      WhatId = accountId,
      Subject = subject,
      Type = type,
      Description = subject + ' description',
      StartDateTime = start,
      EndDateTime = start.addMinutes(60)
    );
  }

  /**
   * Publishing an Action Plan Template Version requires at least one item, and each Task item
   * requires Subject / Priority / ActivityDate values, so the template is built in full here.
   */
  private static Id buildPublishedTemplateVersion(List<String> stepNames) {
    String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    ActionPlanTemplate template = new ActionPlanTemplate(
      Name = 'CX Timeline Test Template',
      UniqueName = 'CX_Timeline_Test_Template_' + suffix,
      TargetEntityType = 'Account',
      ActionPlanType = 'Sales',
      Description = 'Template used to prove playbook steps stay off the timeline.'
    );
    insert template;

    ActionPlanTemplateVersion version = [
      SELECT Id, Status
      FROM ActionPlanTemplateVersion
      WHERE ActionPlanTemplateId = :template.Id
      LIMIT 1
    ];

    List<ActionPlanTemplateItem> templateItems = new List<ActionPlanTemplateItem>();
    for (Integer i = 0; i < stepNames.size(); i++) {
      templateItems.add(
        new ActionPlanTemplateItem(
          Name = stepNames[i],
          UniqueName = 'CX_Timeline_Test_Step_' + i + '_' + suffix,
          ActionPlanTemplateVersionId = version.Id,
          ItemEntityType = 'Task',
          DisplayOrder = i + 1,
          IsRequired = true,
          IsActive = true
        )
      );
    }
    insert templateItems;

    List<ActionPlanTemplateItemValue> values = new List<ActionPlanTemplateItemValue>();
    for (Integer i = 0; i < templateItems.size(); i++) {
      Id itemId = templateItems[i].Id;
      values.add(
        new ActionPlanTemplateItemValue(
          Name = 'Subject',
          ActionPlanTemplateItemId = itemId,
          ItemEntityFieldName = 'Task.Subject',
          ValueLiteral = stepNames[i],
          IsActive = true
        )
      );
      values.add(
        new ActionPlanTemplateItemValue(
          Name = 'Priority',
          ActionPlanTemplateItemId = itemId,
          ItemEntityFieldName = 'Task.Priority',
          ValueLiteral = 'Normal',
          IsActive = true
        )
      );
      values.add(
        new ActionPlanTemplateItemValue(
          Name = 'ActivityDate',
          ActionPlanTemplateItemId = itemId,
          ItemEntityFieldName = 'Task.ActivityDate',
          ValueFormula = 'StartDate + ' + i,
          IsActive = true
        )
      );
    }
    insert values;

    version.Status = 'Final';
    update version;
    return version.Id;
  }

  /** Creating the plan makes the platform generate the Tasks and the ActionPlanItem rows. */
  private static ActionPlan buildPlan(Id accountId, List<String> stepNames) {
    ActionPlan plan = new ActionPlan(
      Name = 'RISK: CX Timeline Test Plan',
      TargetId = accountId,
      ActionPlanTemplateVersionId = buildPublishedTemplateVersion(stepNames),
      ActionPlanType = 'Sales',
      ActionPlanState = 'In Progress',
      StartDate = TODAY
    );
    insert plan;
    return plan;
  }

  private static User newUser(String profileName) {
    Profile profile = [
      SELECT Id
      FROM Profile
      WHERE Name = :profileName
      LIMIT 1
    ];
    String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
    User user = new User(
      ProfileId = profile.Id,
      LastName = 'CxTimeline',
      Email = 'cx.timeline.' + unique + '@example.com',
      Username = 'cx.timeline.' + unique + '@example.com.cxtest',
      Alias = 'cxtl',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert user;
    return user;
  }

  private static List<String> subjectsOf(
    NavexCxTimelineController.Timeline timeline
  ) {
    List<String> subjects = new List<String>();
    for (NavexCxTimelineController.Milestone milestone : timeline.milestones) {
      subjects.add(milestone.subject);
    }
    return subjects;
  }

  private static Map<String, NavexCxTimelineController.Milestone> bySubject(
    NavexCxTimelineController.Timeline timeline
  ) {
    Map<String, NavexCxTimelineController.Milestone> result = new Map<String, NavexCxTimelineController.Milestone>();
    for (NavexCxTimelineController.Milestone milestone : timeline.milestones) {
      result.put(milestone.subject, milestone);
    }
    return result;
  }

  // ---------------------------------------------------------------- ordering

  @IsTest
  static void mergesTasksAndEventsIntoOneChronologicalRun() {
    Account account = newAccount();
    insert new List<Task>{
      newTask(
        account.Id,
        'Onboarding complete',
        'Other',
        'Completed',
        TODAY.addMonths(-10)
      ),
      newTask(
        account.Id,
        'Adoption alert',
        'Other',
        'Completed',
        TODAY.addMonths(-2)
      )
    };
    insert new List<Event>{
      newEvent(account.Id, 'Platform kickoff', 'Meeting', TODAY.addMonths(-14)),
      newEvent(
        account.Id,
        'Executive business review',
        'Meeting',
        TODAY.addMonths(-6)
      )
    };

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{
        'Platform kickoff',
        'Onboarding complete',
        'Executive business review',
        'Adoption alert'
      },
      subjectsOf(result),
      'Tasks and Events should interleave in date order, oldest first'
    );
    Assert.areEqual(4, result.totalCount, 'All four activities are milestones');
    Assert.areEqual(4, result.availableCount, 'Nothing was dropped by the max');
    Assert.isFalse(result.isTruncated, 'Four rows fit inside the max of 20');
    Assert.areEqual(
      account.Id,
      result.accountId,
      'The requested account is echoed back'
    );
    Assert.areEqual(
      'CX Timeline Test Account',
      result.accountName,
      'The account name is returned for the card subtitle'
    );

    Map<String, NavexCxTimelineController.Milestone> milestones = bySubject(
      result
    );
    Assert.areEqual(
      'Event',
      milestones.get('Platform kickoff').objectApiName,
      'Events report their own object so the link resolves'
    );
    Assert.areEqual(
      'Task',
      milestones.get('Adoption alert').objectApiName,
      'Tasks report their own object so the link resolves'
    );
    Assert.areEqual(
      'Adoption alert description',
      milestones.get('Adoption alert').description,
      'The description feeds the detail panel'
    );
    Assert.areEqual(
      'Meeting',
      milestones.get('Platform kickoff').activityType,
      'Type drives the category mapping in the component'
    );
    // ownerName is deliberately not asserted here. The Owner lookup on Task and Event is
    // polymorphic and does not resolve under test isolation, so a unit test can only ever
    // prove it is null. It is verified against real records with
    // scripts/apex/navex_cx_timeline_data.apex instead.
    Assert.areEqual(
      'Completed',
      milestones.get('Adoption alert').status,
      'Task status is passed through for the detail panel'
    );
  }

  @IsTest
  static void ordersSameDayMilestonesDeterministically() {
    Account account = newAccount();
    insert new List<Task>{
      newTask(
        account.Id,
        'Beta review',
        'Call',
        'Completed',
        TODAY.addDays(-5)
      ),
      newTask(
        account.Id,
        'Alpha review',
        'Call',
        'Completed',
        TODAY.addDays(-5)
      )
    };

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Alpha review', 'Beta review' },
      subjectsOf(result),
      'Milestones sharing a date fall back to subject order'
    );
  }

  // ---------------------------------------------------------------- playbook exclusion

  @IsTest
  static void excludesActionPlanPlaybookSteps() {
    Account account = newAccount();
    Task csmActivity = newTask(
      account.Id,
      'Adoption review',
      'Meeting',
      'Completed',
      TODAY.addMonths(-3)
    );
    insert csmActivity;
    buildPlan(
      account.Id,
      new List<String>{ '1: Internal Sync', '2: Customer Discovery' }
    );

    // The plan really did generate its checklist tasks against this account.
    Assert.areEqual(
      3,
      [SELECT COUNT() FROM Task WHERE WhatId = :account.Id],
      'The account should hold the CSM activity plus two generated playbook tasks'
    );

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Adoption review' },
      subjectsOf(result),
      'Only the CSM activity belongs on the timeline'
    );
    Assert.areEqual(
      1,
      result.availableCount,
      'Playbook steps are removed before the max is applied'
    );
    Assert.isTrue(
      result.excludesPlaybookSteps,
      'An admin can read ActionPlanItem, so the exclusion is guaranteed'
    );
  }

  // ---------------------------------------------------------------- milestonesOnly

  /**
   * Seeds an account with two flagged lifecycle milestones (one Task, one Event) and two
   * unflagged day-to-day activities, which is the shape of the real Meridian data.
   */
  private static Account accountWithFlaggedAndUnflaggedActivities() {
    Account account = newAccount();

    Task flaggedTask = newTask(
      account.Id,
      'Adoption alert',
      'Other',
      'Completed',
      TODAY.addMonths(-4)
    );
    flaggedTask.CX_Milestone__c = true;
    Task everydayTask = newTask(
      account.Id,
      'Follow-up: Share PolicyTech feature roadmap',
      'Email',
      'Completed',
      TODAY.addMonths(-3)
    );
    insert new List<Task>{ flaggedTask, everydayTask };

    Event flaggedEvent = newEvent(
      account.Id,
      'Platform kickoff',
      'Meeting',
      TODAY.addMonths(-16)
    );
    flaggedEvent.CX_Milestone__c = true;
    Event everydayEvent = newEvent(
      account.Id,
      'Weekly sync',
      'Meeting',
      TODAY.addMonths(-1)
    );
    insert new List<Event>{ flaggedEvent, everydayEvent };

    return account;
  }

  @IsTest
  static void returnsOnlyFlaggedActivitiesWhenMilestonesOnlyIsOn() {
    Account account = accountWithFlaggedAndUnflaggedActivities();

    Test.startTest();
    NavexCxTimelineController.Timeline result = NavexCxTimelineController.getTimeline(
      account.Id,
      20,
      true,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Platform kickoff', 'Adoption alert' },
      subjectsOf(result),
      'Only the flagged Task and Event reach the timeline, still oldest-first'
    );
    Assert.areEqual(2, result.totalCount, 'Two flagged activities');
    Assert.areEqual(
      2,
      result.availableCount,
      'The unflagged rows are filtered in the query, so they never count as available'
    );
    Assert.isTrue(
      result.milestonesOnlyRequested,
      'The request is echoed back for the component to reason about'
    );
    Assert.isTrue(
      result.milestonesOnlyApplied,
      'The field is deployed and readable here, so the filter really was applied'
    );
  }

  @IsTest
  static void returnsEveryActivityWhenMilestonesOnlyIsOff() {
    Account account = accountWithFlaggedAndUnflaggedActivities();

    Test.startTest();
    NavexCxTimelineController.Timeline result = NavexCxTimelineController.getTimeline(
      account.Id,
      20,
      true,
      false
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{
        'Platform kickoff',
        'Adoption alert',
        'Follow-up: Share PolicyTech feature roadmap',
        'Weekly sync'
      },
      subjectsOf(result),
      'With the filter off the whole activity history is plotted'
    );
    Assert.isFalse(
      result.milestonesOnlyRequested,
      'The page did not ask for the filter'
    );
    Assert.isFalse(
      result.milestonesOnlyApplied,
      'Nothing was filtered, so nothing is reported as applied'
    );
  }

  @IsTest
  static void treatsNullMilestonesOnlyAsOff() {
    Account account = accountWithFlaggedAndUnflaggedActivities();

    Test.startTest();
    NavexCxTimelineController.Timeline result = NavexCxTimelineController.getTimeline(
      account.Id,
      20,
      true,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      4,
      result.totalCount,
      'A null flag is treated as false rather than throwing'
    );
    Assert.isFalse(result.milestonesOnlyApplied, 'No filter was applied');
  }

  @IsTest
  static void fallsBackToEveryActivityWhenTheMilestoneFieldIsNotDeployed() {
    // Simulates an org that never deployed CX_Milestone__c. The card must still show the
    // account's history: a demo going blank because of a missing field is the worst outcome.
    Account account = accountWithFlaggedAndUnflaggedActivities();
    NavexCxTimelineController.milestoneFieldOverride = 'Not_A_Real_Field__c';

    Test.startTest();
    NavexCxTimelineController.Timeline result = NavexCxTimelineController.getTimeline(
      account.Id,
      20,
      true,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      4,
      result.totalCount,
      'Every activity is returned rather than an empty timeline'
    );
    Assert.isTrue(
      result.milestonesOnlyRequested,
      'The page still asked for the curated view'
    );
    Assert.isFalse(
      result.milestonesOnlyApplied,
      'The component is told the filter could not be honoured'
    );
  }

  @IsTest
  static void detectsWhetherTheMilestoneFieldExistsOnAGivenObject() {
    Test.startTest();
    Boolean onTask = NavexCxTimelineController.hasMilestoneField(
      Task.SObjectType
    );
    Boolean onEvent = NavexCxTimelineController.hasMilestoneField(
      Event.SObjectType
    );
    // Account is a stand-in for any object the field was not defined on.
    Boolean onAccount = NavexCxTimelineController.hasMilestoneField(
      Account.SObjectType
    );
    Test.stopTest();

    Assert.isTrue(
      onTask,
      'One Activity field definition makes CX_Milestone__c available to Task'
    );
    Assert.isTrue(
      onEvent,
      'The same definition makes it available to Event, with no second field'
    );
    Assert.isFalse(
      onAccount,
      'An object without the field reports false instead of throwing'
    );
  }

  @IsTest
  static void appliesThePlaybookExclusionIndependentlyOfMilestonesOnly() {
    // The two filters must compose: a playbook step that somehow carries the milestone flag is
    // still a playbook step and still belongs on the CTA page, not the timeline.
    Account account = newAccount();
    Task lifecycleMilestone = newTask(
      account.Id,
      'Adoption review',
      'Meeting',
      'Completed',
      TODAY.addMonths(-3)
    );
    lifecycleMilestone.CX_Milestone__c = true;
    insert lifecycleMilestone;

    buildPlan(
      account.Id,
      new List<String>{ '1: Internal Sync', '2: Customer Discovery' }
    );
    List<Task> playbookTasks = [
      SELECT Id
      FROM Task
      WHERE WhatId = :account.Id AND Subject LIKE '%: %'
    ];
    Assert.areEqual(
      2,
      playbookTasks.size(),
      'The plan generated its two checklist tasks'
    );
    for (Task playbookTask : playbookTasks) {
      playbookTask.CX_Milestone__c = true;
    }
    update playbookTasks;

    Test.startTest();
    NavexCxTimelineController.Timeline result = NavexCxTimelineController.getTimeline(
      account.Id,
      20,
      true,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Adoption review' },
      subjectsOf(result),
      'A flagged playbook step is still excluded, so the two filters are independent'
    );
    Assert.isTrue(
      result.excludesPlaybookSteps,
      'The playbook exclusion is still reported as guaranteed'
    );
    Assert.isTrue(
      result.milestonesOnlyApplied,
      'The milestone filter was applied as well'
    );
  }

  // ---------------------------------------------------------------- undated

  @IsTest
  static void pinsUndatedActivitiesToTheEndWithoutBreakingTheSort() {
    Account account = newAccount();
    insert new List<Task>{
      newTask(
        account.Id,
        'Dated milestone',
        'Call',
        'Completed',
        TODAY.addMonths(-1)
      ),
      newTask(
        account.Id,
        'Discovery call - initial outreach',
        'Call',
        'Completed',
        null
      ),
      newTask(
        account.Id,
        'Older milestone',
        'Call',
        'Completed',
        TODAY.addMonths(-4)
      )
    };

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{
        'Older milestone',
        'Dated milestone',
        'Discovery call - initial outreach'
      },
      subjectsOf(result),
      'A null ActivityDate sorts last instead of corrupting the order'
    );

    Map<String, NavexCxTimelineController.Milestone> milestones = bySubject(
      result
    );
    NavexCxTimelineController.Milestone undated = milestones.get(
      'Discovery call - initial outreach'
    );
    Assert.isTrue(undated.isUndated, 'The undated activity is flagged');
    Assert.isNull(undated.activityDate, 'The undated activity has no date');
    Assert.isFalse(
      undated.isFuture,
      'An activity with no date cannot be in the future'
    );
    Assert.isFalse(
      milestones.get('Dated milestone').isUndated,
      'A dated activity is not flagged as undated'
    );
  }

  // ---------------------------------------------------------------- past / future

  @IsTest
  static void flagsPastAndFutureMilestones() {
    Account account = newAccount();
    insert new List<Task>{
      newTask(
        account.Id,
        'Completed check-in',
        'Call',
        'Completed',
        TODAY.addDays(-30)
      ),
      newTask(account.Id, 'Due today', 'Call', 'Not Started', TODAY),
      newTask(
        account.Id,
        'Upcoming readout',
        'Call',
        'Not Started',
        TODAY.addDays(30)
      )
    };
    insert newEvent(
      account.Id,
      'Future planning session',
      'Meeting',
      TODAY.addDays(45)
    );
    insert newEvent(account.Id, 'Past kickoff', 'Meeting', TODAY.addDays(-60));

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Map<String, NavexCxTimelineController.Milestone> milestones = bySubject(
      result
    );
    Assert.isFalse(
      milestones.get('Completed check-in').isFuture,
      'A past task is not future'
    );
    Assert.isTrue(
      milestones.get('Completed check-in').isCompleted,
      'A closed task reports as completed'
    );
    Assert.isFalse(
      milestones.get('Due today').isFuture,
      'Today is not the future'
    );
    Assert.isFalse(
      milestones.get('Due today').isCompleted,
      'An open task is not completed'
    );
    Assert.areEqual(
      'Not Started',
      milestones.get('Due today').status,
      'Task status is passed through'
    );
    Assert.isTrue(
      milestones.get('Upcoming readout').isFuture,
      'A task dated after today is future'
    );
    Assert.isTrue(
      milestones.get('Future planning session').isFuture,
      'An event dated after today is future'
    );
    Assert.isFalse(
      milestones.get('Future planning session').isCompleted,
      'A future event has not happened yet'
    );
    Assert.isTrue(
      milestones.get('Past kickoff').isCompleted,
      'A past event has happened, which is the closest an Event has to a status'
    );
    Assert.isNull(
      milestones.get('Past kickoff').status,
      'Events carry no status field'
    );
  }

  @IsTest
  static void omitsFutureActivitiesWhenIncludeFutureIsFalse() {
    Account account = newAccount();
    insert new List<Task>{
      newTask(
        account.Id,
        'Past milestone',
        'Call',
        'Completed',
        TODAY.addDays(-10)
      ),
      newTask(
        account.Id,
        'Future milestone',
        'Call',
        'Not Started',
        TODAY.addDays(10)
      ),
      newTask(account.Id, 'Undated milestone', 'Call', 'Completed', null)
    };
    insert newEvent(account.Id, 'Future event', 'Meeting', TODAY.addDays(20));

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      false
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Past milestone', 'Undated milestone' },
      subjectsOf(result),
      'Future activities are excluded, undated ones are kept'
    );
  }

  @IsTest
  static void treatsNullIncludeFutureAsExcludingFutureActivities() {
    Account account = newAccount();
    insert new List<Task>{
      newTask(
        account.Id,
        'Past milestone',
        'Call',
        'Completed',
        TODAY.addDays(-10)
      ),
      newTask(
        account.Id,
        'Future milestone',
        'Call',
        'Not Started',
        TODAY.addDays(10)
      )
    };

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      null
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Past milestone' },
      subjectsOf(result),
      'A null flag is treated as false rather than throwing'
    );
  }

  // ---------------------------------------------------------------- max milestones

  @IsTest
  static void keepsTheNewestMilestonesWhenTheMaxIsExceeded() {
    Account account = newAccount();
    List<Task> tasks = new List<Task>();
    for (Integer i = 1; i <= 6; i++) {
      tasks.add(
        newTask(
          account.Id,
          'Milestone ' + i,
          'Call',
          'Completed',
          TODAY.addMonths(-i)
        )
      );
    }
    insert tasks;

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      3,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Milestone 3', 'Milestone 2', 'Milestone 1' },
      subjectsOf(result),
      'The three most recent milestones survive, still oldest-first'
    );
    Assert.areEqual(3, result.totalCount, 'Only the max is returned');
    Assert.areEqual(
      6,
      result.availableCount,
      'The full count is reported so the component can say so'
    );
    Assert.isTrue(result.isTruncated, 'The caller is told the list was cut');
  }

  @IsTest
  static void fallsBackToTheDefaultMaxForNullAndNonPositiveValues() {
    Account account = newAccount();
    List<Task> tasks = new List<Task>();
    for (Integer i = 1; i <= 3; i++) {
      tasks.add(
        newTask(
          account.Id,
          'Milestone ' + i,
          'Call',
          'Completed',
          TODAY.addMonths(-i)
        )
      );
    }
    insert tasks;

    Test.startTest();
    NavexCxTimelineController.Timeline nullMax = timelineFor(
      account.Id,
      null,
      true
    );
    NavexCxTimelineController.Timeline zeroMax = timelineFor(
      account.Id,
      0,
      true
    );
    NavexCxTimelineController.Timeline negativeMax = timelineFor(
      account.Id,
      -5,
      true
    );
    NavexCxTimelineController.Timeline hugeMax = timelineFor(
      account.Id,
      5000,
      true
    );
    Test.stopTest();

    Assert.areEqual(3, nullMax.totalCount, 'A null max uses the default');
    Assert.areEqual(3, zeroMax.totalCount, 'A zero max uses the default');
    Assert.areEqual(
      3,
      negativeMax.totalCount,
      'A negative max uses the default'
    );
    Assert.areEqual(
      3,
      hugeMax.totalCount,
      'A max above the ceiling is capped but still returns everything available'
    );
    Assert.isFalse(nullMax.isTruncated, 'Three rows fit inside the default');
  }

  // ---------------------------------------------------------------- empty state

  @IsTest
  static void returnsAnEmptyTimelineForAnAccountWithNoActivities() {
    Account account = newAccount();

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Assert.areEqual(0, result.totalCount, 'There is nothing to show');
    Assert.areEqual(
      0,
      result.availableCount,
      'Nothing was filtered out either'
    );
    Assert.isFalse(result.isTruncated, 'An empty list is not truncated');
    Assert.isNotNull(result.milestones, 'An empty list, never null');
    Assert.isTrue(result.milestones.isEmpty(), 'An empty list, never null');
    Assert.areEqual(
      'CX Timeline Test Account',
      result.accountName,
      'The account still resolves so the card can render its header'
    );
  }

  @IsTest
  static void labelsActivitiesThatHaveNoSubject() {
    Account account = newAccount();
    insert newTask(account.Id, null, 'Call', 'Completed', TODAY.addDays(-3));
    Event evt = newEvent(
      account.Id,
      'placeholder',
      'Meeting',
      TODAY.addDays(-2)
    );
    evt.Subject = null;
    insert evt;

    Test.startTest();
    NavexCxTimelineController.Timeline result = timelineFor(
      account.Id,
      20,
      true
    );
    Test.stopTest();

    Assert.areEqual(
      new List<String>{ 'Untitled activity', 'Untitled event' },
      subjectsOf(result),
      'A blank subject gets a readable placeholder instead of an empty node'
    );
  }

  // ---------------------------------------------------------------- validation

  @IsTest
  static void rejectsARecordIdThatIsNotAnAccount() {
    Account account = newAccount();
    Task task = newTask(
      account.Id,
      'Not an account',
      'Call',
      'Completed',
      TODAY
    );
    insert task;

    Test.startTest();
    try {
      timelineFor(task.Id, 20, true);
      Assert.fail('A non-Account record id should be rejected');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        'This component must be placed on an Account record page.',
        e.getMessage(),
        'The message should tell the admin where the component belongs'
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void rejectsANullRecordId() {
    Test.startTest();
    try {
      timelineFor(null, 20, true);
      Assert.fail('A null record id should be rejected');
    } catch (AuraHandledException e) {
      Assert.areEqual(
        'This component must be placed on an Account record page.',
        e.getMessage(),
        'The same guidance covers a missing record id'
      );
    }
    Test.stopTest();
  }

  // ---------------------------------------------------------------- security

  @IsTest
  static void refusesAnAccountTheRunningUserCannotSee() {
    Account account = newAccount();
    User minimumAccess = newUser('Minimum Access - Salesforce');

    Test.startTest();
    System.runAs(minimumAccess) {
      try {
        timelineFor(account.Id, 20, true);
        Assert.fail('A user without Account access should not get a timeline');
      } catch (AuraHandledException e) {
        Assert.areEqual(
          'This account could not be found, or you don\'t have access to it.',
          e.getMessage(),
          'The user is told the record is not visible rather than seeing data'
        );
      }
    }
    Test.stopTest();
  }

  @IsTest
  static void stillFiltersPlaybookStepsForARestrictedUser() {
    // A Standard User reaches the account through ownership rather than through admin rights.
    // Nothing is asserted about which activities come back: whether this profile can read Task
    // and Event is org configuration, and the point here is that the component still renders
    // and still reports the playbook filter as applied.
    User standardUser = newUser('Standard User');
    Account account = newAccount(standardUser.Id);
    Task task = newTask(
      account.Id,
      'Health check',
      'Call',
      'Completed',
      TODAY.addDays(-15)
    );
    task.OwnerId = standardUser.Id;
    insert task;

    NavexCxTimelineController.Timeline result;
    Test.startTest();
    System.runAs(standardUser) {
      result = timelineFor(account.Id, 20, true);
    }
    Test.stopTest();

    Assert.isNotNull(
      result,
      'A restricted user gets a timeline rather than an exception'
    );
    Assert.isNotNull(result.milestones, 'An empty list, never null');
    Assert.isTrue(
      result.excludesPlaybookSteps,
      'This profile can read ActionPlanItem, so playbook steps are still filtered out'
    );
  }

  @IsTest
  static void keepsRenderingWhenOneActivityObjectIsUnreadable() {
    // Losing read access to Task or Event should thin the timeline out, not blank the page.
    User standardUser = newUser('Standard User');
    Account account = newAccount(standardUser.Id);

    NavexCxTimelineController.Timeline result;
    Test.startTest();
    System.runAs(standardUser) {
      result = timelineFor(account.Id, 20, true);
    }
    Test.stopTest();

    Assert.areEqual(
      'CX Timeline Test Account',
      result.accountName,
      'The account header still resolves for a restricted user'
    );
    Assert.areEqual(
      0,
      result.totalCount,
      'An account with no readable activities reports an empty timeline'
    );
  }
}
