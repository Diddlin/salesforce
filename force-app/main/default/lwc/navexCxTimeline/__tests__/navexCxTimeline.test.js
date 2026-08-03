import { createElement } from "lwc";
import NavexCxTimeline from "c/navexCxTimeline";
import getTimeline from "@salesforce/apex/NavexCxTimelineController.getTimeline";
import { resolveCategory } from "../milestoneCategory";

const mockNavigate = jest.fn();
const mockGenerateUrl = jest.fn((config) =>
  Promise.resolve(
    `/lightning/r/${config.attributes.objectApiName}/${config.attributes.recordId}/view`
  )
);

jest.mock("lightning/navigation", () => {
  const Navigate = Symbol("Navigate");
  const GenerateUrl = Symbol("GenerateUrl");
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](...args) {
        return mockNavigate(...args);
      }
      [GenerateUrl](...args) {
        return mockGenerateUrl(...args);
      }
    };
  NavigationMixin.Navigate = Navigate;
  NavigationMixin.GenerateUrl = GenerateUrl;
  return { NavigationMixin, CurrentPageReference: jest.fn() };
});

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/NavexCxTimelineController.getTimeline",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const ACCOUNT_ID = "001Hs00005wLdgKIAS";
const KICKOFF_ID = "00UHs00000000K1MAI";
const ALERT_ID = "00THs0000EDfvnMMQR";
const EBR_ID = "00UHs00000000E1MAI";
const FUTURE_ID = "00THs0000EDfvnSMQR";
const UNDATED_ID = "00THs0000EDepMUMQZ";

function milestone(overrides = {}) {
  return {
    recordId: ALERT_ID,
    objectApiName: "Task",
    subject: "Adoption alert",
    description: "Active users at cycle low.",
    activityDate: "2026-03-12",
    activityType: "Other",
    status: "Completed",
    ownerName: "Priya Nair",
    isCompleted: true,
    isFuture: false,
    isUndated: false,
    ...overrides
  };
}

function timelineFixture(overrides = {}) {
  return {
    accountId: ACCOUNT_ID,
    accountName: "Meridian Health",
    totalCount: 3,
    availableCount: 3,
    isTruncated: false,
    excludesPlaybookSteps: true,
    milestonesOnlyRequested: true,
    milestonesOnlyApplied: true,
    milestones: [
      milestone({
        recordId: KICKOFF_ID,
        objectApiName: "Event",
        subject: "Platform kickoff",
        description: "EthicsPoint Hotline and PolicyTech kickoff.",
        activityDate: "2025-03-11",
        activityType: "Meeting",
        status: null
      }),
      milestone(),
      milestone({
        recordId: EBR_ID,
        objectApiName: "Event",
        subject: "EBR - Sarah Okonkowo",
        description: "Executive business review.",
        activityDate: "2026-04-16",
        activityType: "Meeting",
        status: null
      })
    ],
    ...overrides
  };
}

function createComponent(props = {}) {
  const element = createElement("c-navex-cx-timeline", {
    is: NavexCxTimeline
  });
  element.recordId = ACCOUNT_ID;
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

function flushPromises() {
  return Promise.resolve().then(() => Promise.resolve());
}

function nodes(element) {
  return Array.from(element.shadowRoot.querySelectorAll(".cx-node__button"));
}

function textOf(element, selector) {
  const found = element.shadowRoot.querySelector(selector);
  return found ? found.textContent.trim() : null;
}

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-navex-cx-timeline rendering", () => {
  it("shows a loading state before any data arrives", () => {
    const element = createComponent();

    expect(element.shadowRoot.querySelector(".skeleton")).not.toBeNull();
    expect(nodes(element)).toHaveLength(0);
  });

  it("renders one node per milestone in the order the server returned them", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const rendered = nodes(element);
    expect(rendered).toHaveLength(3);

    const titles = rendered.map((node) =>
      node.querySelector(".cx-node__title").textContent.trim()
    );
    expect(titles).toEqual([
      "Platform kickoff",
      "Adoption alert",
      "EBR - Sarah Okonkowo"
    ]);
  });

  it("labels each node with an abbreviated month and year", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const dates = nodes(element).map((node) =>
      node.querySelector(".cx-node__date").textContent.trim()
    );
    expect(dates).toEqual(["Mar '25", "Mar '26", "Apr '26"]);
  });

  it("shows the milestone count in the card header", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    expect(textOf(element, ".count-pill")).toBe("3 milestones");
  });

  it("uses the singular noun for a single milestone", async () => {
    const element = createComponent();
    getTimeline.emit(
      timelineFixture({
        totalCount: 1,
        availableCount: 1,
        milestones: [milestone()]
      })
    );
    await flushPromises();

    expect(textOf(element, ".count-pill")).toBe("1 milestone");
  });

  it("reports when the list was cut short by the maximum", async () => {
    const element = createComponent();
    getTimeline.emit(
      timelineFixture({ totalCount: 3, availableCount: 17, isTruncated: true })
    );
    await flushPromises();

    expect(textOf(element, ".cx-note")).toBe(
      "Showing the 3 most recent of 17 activities."
    );
  });

  it("marks a future milestone as upcoming instead of hiding it", async () => {
    const element = createComponent();
    getTimeline.emit(
      timelineFixture({
        totalCount: 1,
        availableCount: 1,
        milestones: [
          milestone({
            recordId: FUTURE_ID,
            subject: "Customer readout",
            activityDate: "2026-12-14",
            isFuture: true,
            isCompleted: false,
            status: "Not Started"
          })
        ]
      })
    );
    await flushPromises();

    const [node] = nodes(element);
    expect(node.getAttribute("aria-label")).toBe(
      "Dec '26, Customer readout, Activity, upcoming"
    );
    expect(node.querySelector(".cx-node__marker").className).toContain(
      "cx-node__marker_future"
    );
  });

  it("renders an undated activity without breaking the row", async () => {
    const element = createComponent();
    getTimeline.emit(
      timelineFixture({
        totalCount: 1,
        availableCount: 1,
        milestones: [
          milestone({
            recordId: UNDATED_ID,
            subject: "Discovery call - initial outreach",
            activityDate: null,
            isUndated: true
          })
        ]
      })
    );
    await flushPromises();

    const [node] = nodes(element);
    expect(node.querySelector(".cx-node__date").textContent.trim()).toBe(
      "No date"
    );
  });
});

describe("c-navex-cx-timeline detail panel", () => {
  it("opens the panel with the milestone's content when a node is clicked", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    expect(element.shadowRoot.querySelector(".cx-detail")).toBeNull();

    nodes(element)[1].click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".cx-detail")).not.toBeNull();
    expect(textOf(element, ".cx-detail__title")).toBe("Adoption alert");
    expect(textOf(element, ".cx-detail__pill")).toBe("Risk");
    expect(textOf(element, ".cx-detail__date")).toBe("12 Mar 2026");
    expect(textOf(element, ".cx-detail__body")).toBe(
      "Active users at cycle low."
    );
    expect(textOf(element, ".cx-detail__owner")).toBe("Logged by Priya Nair");
  });

  it("marks the open node as expanded for assistive technology", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[1].click();
    await flushPromises();

    const rendered = nodes(element);
    expect(rendered[1].getAttribute("aria-expanded")).toBe("true");
    expect(rendered[0].getAttribute("aria-expanded")).toBe("false");
    // LWC rewrites template ids to keep them unique in the document, so the node's
    // aria-controls is compared against the id the panel actually rendered with.
    const panelId = element.shadowRoot
      .querySelector(".cx-detail")
      .getAttribute("id");
    expect(panelId).toBeTruthy();
    expect(rendered[1].getAttribute("aria-controls")).toBe(panelId);
  });

  it("links to the underlying record with a real href", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[2].click();
    await flushPromises();

    const link = element.shadowRoot.querySelector(".cx-detail__link");
    expect(link.getAttribute("href")).toBe(`/lightning/r/Event/${EBR_ID}/view`);
    expect(link.textContent.trim()).toBe("Open this event");
  });

  it("navigates client-side when the record link is activated", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[1].click();
    await flushPromises();

    element.shadowRoot.querySelector(".cx-detail__link").click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: ALERT_ID,
        objectApiName: "Task",
        actionName: "view"
      }
    });
  });

  it("closes the panel from the dismiss control", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[1].click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".cx-detail")).not.toBeNull();

    element.shadowRoot.querySelector(".cx-detail__dismiss").click();
    await flushPromises();

    expect(element.shadowRoot.querySelector(".cx-detail")).toBeNull();
  });

  it("returns focus to the node that opened the panel after dismissing", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[1].click();
    await flushPromises();

    element.shadowRoot.querySelector(".cx-detail__dismiss").click();
    await flushPromises();

    expect(element.shadowRoot.activeElement).toBe(nodes(element)[1]);
  });

  it("closes the panel when the same node is clicked again", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[0].click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".cx-detail")).not.toBeNull();

    nodes(element)[0].click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".cx-detail")).toBeNull();
  });

  it("explains when an activity carries no description", async () => {
    const element = createComponent();
    getTimeline.emit(
      timelineFixture({
        totalCount: 1,
        availableCount: 1,
        milestones: [milestone({ description: null })]
      })
    );
    await flushPromises();

    nodes(element)[0].click();
    await flushPromises();

    expect(textOf(element, ".cx-detail__body")).toBe(
      "No description was recorded on this activity."
    );
  });

  it("drops the open panel when the milestone disappears from refreshed data", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element)[1].click();
    await flushPromises();
    expect(element.shadowRoot.querySelector(".cx-detail")).not.toBeNull();

    getTimeline.emit(
      timelineFixture({
        totalCount: 1,
        availableCount: 1,
        milestones: [
          milestone({ recordId: KICKOFF_ID, subject: "Platform kickoff" })
        ]
      })
    );
    await flushPromises();

    expect(element.shadowRoot.querySelector(".cx-detail")).toBeNull();
  });
});

describe("c-navex-cx-timeline keyboard support", () => {
  it("gives every node an accessible name containing its date and title", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const labels = nodes(element).map((node) =>
      node.getAttribute("aria-label")
    );
    expect(labels).toEqual([
      "Mar '25, Platform kickoff, Kickoff",
      "Mar '26, Adoption alert, Risk",
      "Apr '26, EBR - Sarah Okonkowo, Business review"
    ]);
  });

  it("renders nodes as real buttons so they are keyboard operable", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    nodes(element).forEach((node) => {
      expect(node.tagName).toBe("BUTTON");
      expect(node.getAttribute("type")).toBe("button");
    });
  });

  it("moves focus along the row with the arrow keys", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const rendered = nodes(element);
    rendered[0].focus();

    rendered[0].dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true })
    );
    await flushPromises();
    expect(element.shadowRoot.activeElement).toBe(rendered[1]);

    rendered[1].dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true })
    );
    await flushPromises();
    expect(element.shadowRoot.activeElement).toBe(rendered[0]);
  });

  it("jumps to the ends of the row with Home and End", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const rendered = nodes(element);
    rendered[0].focus();

    rendered[0].dispatchEvent(
      new KeyboardEvent("keydown", { key: "End", bubbles: true })
    );
    await flushPromises();
    expect(element.shadowRoot.activeElement).toBe(rendered[2]);

    rendered[2].dispatchEvent(
      new KeyboardEvent("keydown", { key: "Home", bubbles: true })
    );
    await flushPromises();
    expect(element.shadowRoot.activeElement).toBe(rendered[0]);
  });

  it("stops at the ends rather than wrapping around", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const rendered = nodes(element);
    rendered[0].focus();
    rendered[0].dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowLeft", bubbles: true })
    );
    await flushPromises();

    expect(element.shadowRoot.activeElement).toBe(rendered[0]);
  });

  it("ignores keys it does not handle", async () => {
    const element = createComponent();
    getTimeline.emit(timelineFixture());
    await flushPromises();

    const rendered = nodes(element);
    rendered[1].focus();
    rendered[1].dispatchEvent(
      new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true })
    );
    await flushPromises();

    expect(element.shadowRoot.activeElement).toBe(rendered[1]);
  });
});

describe("c-navex-cx-timeline empty and error states", () => {
  it("shows the empty state when the account has no milestones", async () => {
    const element = createComponent();
    getTimeline.emit(
      timelineFixture({ totalCount: 0, availableCount: 0, milestones: [] })
    );
    await flushPromises();

    expect(element.shadowRoot.querySelector(".empty-state")).not.toBeNull();
    expect(textOf(element, ".empty-state__title")).toBe("No milestones yet");
    expect(element.shadowRoot.querySelector(".cx-track")).toBeNull();
    expect(element.shadowRoot.querySelector(".count-pill")).toBeNull();
  });

  it("shows a configurable empty state message", async () => {
    const element = createComponent({ emptyMessage: "Nothing logged yet." });
    getTimeline.emit(
      timelineFixture({ totalCount: 0, availableCount: 0, milestones: [] })
    );
    await flushPromises();

    expect(textOf(element, ".empty-state__message")).toBe(
      "Nothing logged yet."
    );
  });

  it("surfaces the server message when the timeline fails to load", async () => {
    const element = createComponent();
    getTimeline.error(
      { message: "This component must be placed on an Account record page." },
      400
    );
    await flushPromises();

    const error = element.shadowRoot.querySelector(".error-boundary");
    expect(error).not.toBeNull();
    expect(error.getAttribute("role")).toBe("alert");
    expect(textOf(element, ".error-boundary__detail")).toBe(
      "This component must be placed on an Account record page."
    );
    expect(element.shadowRoot.querySelector(".cx-track")).toBeNull();
  });

  it("falls back to a generic message when the error carries no body", async () => {
    const element = createComponent();
    getTimeline.error({});
    await flushPromises();

    expect(textOf(element, ".error-boundary__detail")).toBe(
      "An unexpected error occurred."
    );
  });

  it("keeps rendering the timeline when the milestone filter could not be applied", async () => {
    // The server fell back to every activity because CX_Milestone__c was missing or unreadable.
    // The component's job here is simply not to punish the user for it.
    const element = createComponent({ milestonesOnly: true });
    getTimeline.emit(timelineFixture({ milestonesOnlyApplied: false }));
    await flushPromises();

    expect(nodes(element)).toHaveLength(3);
    expect(element.shadowRoot.querySelector(".empty-state")).toBeNull();
    expect(element.shadowRoot.querySelector(".error-boundary")).toBeNull();
  });

  it("uses a custom card title when one is configured", async () => {
    const element = createComponent({ cardTitle: "Customer Journey" });
    getTimeline.emit(timelineFixture());
    await flushPromises();

    expect(textOf(element, ".card-title__text")).toBe("Customer Journey");
  });
});

describe("c-navex-cx-timeline App Builder configuration", () => {
  it("asks the server for the curated set when Lifecycle Milestones Only is on", async () => {
    createComponent({ milestonesOnly: true, maxMilestones: 20 });
    await flushPromises();

    expect(getTimeline.getLastConfig()).toEqual({
      recordId: ACCOUNT_ID,
      maxMilestones: 20,
      includeFuture: false,
      milestonesOnly: true
    });
  });

  it("defaults to the full activity history", async () => {
    createComponent();
    await flushPromises();

    expect(getTimeline.getLastConfig().milestonesOnly).toBe(false);
  });

  it("coerces the App Builder checkbox from its string form", async () => {
    // A FlexiPage stores every component property as text, so "true" has to mean true.
    createComponent({ milestonesOnly: "true", includeFuture: "true" });
    await flushPromises();

    const config = getTimeline.getLastConfig();
    expect(config.milestonesOnly).toBe(true);
    expect(config.includeFuture).toBe(true);
  });

  it("sends a boolean rather than an arbitrary truthy value", async () => {
    createComponent({ milestonesOnly: "false" });
    await flushPromises();

    expect(getTimeline.getLastConfig().milestonesOnly).toBe(false);
  });
});

describe("milestone category mapping", () => {
  it("prefers a subject match over the activity type", () => {
    expect(
      resolveCategory({ subject: "Adoption alert", activityType: "Call" }).key
    ).toBe("risk");
  });

  it("files a business review ahead of a plain review", () => {
    expect(
      resolveCategory({
        subject: "EBR - Q2 Business Review",
        activityType: "Meeting"
      }).key
    ).toBe("ebr");
    expect(resolveCategory({ subject: "Adoption review" }).key).toBe("review");
  });

  it("files a health check ahead of a plain review", () => {
    expect(resolveCategory({ subject: "Health check" }).key).toBe(
      "healthcheck"
    );
  });

  it("recognises the lifecycle milestones the demo relies on", () => {
    expect(resolveCategory({ subject: "Platform kickoff" }).key).toBe(
      "kickoff"
    );
    expect(resolveCategory({ subject: "Onboarding complete" }).key).toBe(
      "onboarding"
    );
    expect(resolveCategory({ subject: "Champion role change" }).key).toBe(
      "relationship"
    );
    expect(resolveCategory({ subject: "API escalation" }).key).toBe(
      "escalation"
    );
    expect(resolveCategory({ subject: "Renewal planning" }).key).toBe(
      "renewal"
    );
  });

  it("falls back to the activity type when the subject says nothing", () => {
    expect(
      resolveCategory({
        subject: "Follow-up with the team",
        activityType: "Email"
      }).key
    ).toBe("email");
    expect(
      resolveCategory({
        subject: "Follow-up with the team",
        activityType: "Meeting"
      }).key
    ).toBe("meeting");
  });

  it("returns a neutral default rather than nothing", () => {
    expect(resolveCategory({}).key).toBe("activity");
    expect(resolveCategory().key).toBe("activity");
    expect(
      resolveCategory({ subject: "Something else", activityType: "Unmapped" })
        .key
    ).toBe("activity");
  });
});
