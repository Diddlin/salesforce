import { createElement } from "lwc";
import NavexCtaPlaybook from "c/navexCtaPlaybook";
import NavexTaskModal from "c/navexTaskModal";
import LightningConfirm from "lightning/confirm";
import getPlaybook from "@salesforce/apex/NavexCtaPlaybookController.getPlaybook";
import toggleTaskCompletion from "@salesforce/apex/NavexCtaPlaybookController.toggleTaskCompletion";
import addAdHocStep from "@salesforce/apex/NavexCtaPlaybookController.addAdHocStep";
import deleteAdHocStep from "@salesforce/apex/NavexCtaPlaybookController.deleteAdHocStep";

const mockNavigate = jest.fn();
const mockGenerateUrl = jest.fn((config) =>
  Promise.resolve(`/lightning/r/Task/${config.attributes.recordId}/view`)
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
  "c/navexTaskModal",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

jest.mock(
  "lightning/confirm",
  () => ({ __esModule: true, default: { open: jest.fn() } }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex",
  () => ({ refreshApex: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/NavexCtaPlaybookController.getPlaybook",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/NavexCtaPlaybookController.toggleTaskCompletion",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock(
  "@salesforce/apex/NavexCtaPlaybookController.addAdHocStep",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

jest.mock(
  "@salesforce/apex/NavexCtaPlaybookController.deleteAdHocStep",
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const RECORD_ID = "07rHs000000QjpNIAS";
const ACCOUNT_ID = "001Hs00005wLdgKIAS";
const OPEN_TASK_ID = "00THs0000EDfvnTMQR";

function playbookFixture(overrides = {}) {
  return {
    planId: RECORD_ID,
    planName: "RISK: PolicyTech Adoption Review - Meridian",
    state: "In Progress",
    startDate: "2026-07-31",
    endDate: null,
    ctaType: "Risk",
    templateName: "RISK: Adoption - Configuration Review (CS)",
    templateGuidance: "Confirm the risk, agree an action, then close the loop.",
    relatedToId: ACCOUNT_ID,
    canEditTasks: true,
    canCreateSteps: true,
    canDeleteAdHocSteps: true,
    totalCount: 3,
    completedCount: 1,
    percentComplete: 33,
    items: [
      {
        itemId: "07sHs000000QuilIAC",
        taskId: "00THs0000EDfvnUMQR",
        subject: "1: Internal Sync",
        status: "Completed",
        dueDate: "2026-07-20",
        priority: "Normal",
        ownerId: "005Hs00000IcRIkIAN",
        ownerName: "David Mazzeo",
        description: null,
        isRequired: true,
        isWaiting: false,
        isComplete: true,
        isOverdue: false,
        isAdHoc: false,
        displayOrder: 0,
        dependencyStatus: "None"
      },
      {
        itemId: "07sHs000000QuiiIAC",
        taskId: OPEN_TASK_ID,
        subject: "3: Generate Configuration Report",
        status: "Not Started",
        dueDate: "2026-07-01",
        priority: "High",
        ownerId: "005Hs00000I0ccmIAB",
        ownerName: "Sarah Success",
        description: null,
        isRequired: false,
        isWaiting: false,
        isComplete: false,
        isOverdue: true,
        isAdHoc: false,
        displayOrder: 0,
        dependencyStatus: "None"
      },
      {
        itemId: "07sHs000000QuigIAC",
        taskId: null,
        subject: "2: Customer Discovery",
        status: null,
        dueDate: null,
        priority: null,
        ownerId: null,
        ownerName: null,
        description: null,
        isRequired: true,
        isWaiting: true,
        isComplete: false,
        isOverdue: false,
        isAdHoc: false,
        displayOrder: 0,
        dependencyStatus: "WaitingOnPrevious"
      }
    ],
    ...overrides
  };
}

function adHocItem(overrides = {}) {
  return {
    itemId: "07sHs000000AdHoc1",
    taskId: "00THs0000EDfvzWMQR",
    subject: "Call the CISO about the audit trail",
    status: "Not Started",
    dueDate: "2026-08-05",
    priority: "Normal",
    ownerId: "005Hs00000IcRIkIAN",
    ownerName: "David Mazzeo",
    description: null,
    isRequired: false,
    isWaiting: false,
    isComplete: false,
    isOverdue: false,
    isAdHoc: true,
    displayOrder: 1,
    dependencyStatus: "None",
    ...overrides
  };
}

function createComponent(props = {}) {
  const element = createElement("c-navex-cta-playbook", {
    is: NavexCtaPlaybook
  });
  element.recordId = RECORD_ID;
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve();

/** Renders the component with data and lets the GenerateUrl promises settle. */
async function renderWith(playbook = playbookFixture(), props = {}) {
  const element = createComponent(props);
  getPlaybook.emit(playbook);
  await flush();
  await flush();
  return element;
}

const rowMenus = (element) =>
  element.shadowRoot.querySelectorAll("lightning-button-menu");
const subjectLinks = (element) =>
  element.shadowRoot.querySelectorAll("a.playbook-row__subject");
const checkboxes = (element) =>
  element.shadowRoot.querySelectorAll('input[type="checkbox"]');

describe("c-navex-cta-playbook", () => {
  beforeEach(() => {
    NavexTaskModal.open.mockResolvedValue({ status: "cancelled" });
    LightningConfirm.open.mockResolvedValue(false);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  // ------------------------------------------------------------- rendering

  it("shows a loading skeleton before data arrives", () => {
    const element = createComponent();
    expect(element.shadowRoot.querySelector(".skeleton")).not.toBeNull();
    expect(element.shadowRoot.querySelector(".playbook-list")).toBeNull();
  });

  it("renders every step with its subject, plan header and progress", async () => {
    const element = await renderWith();

    expect(element.shadowRoot.querySelectorAll(".playbook-row")).toHaveLength(
      3
    );

    const subjects = Array.from(
      element.shadowRoot.querySelectorAll(".playbook-row__subject")
    ).map((node) => node.textContent.trim());
    expect(subjects).toEqual([
      "1: Internal Sync",
      "3: Generate Configuration Report",
      "2: Customer Discovery"
    ]);

    expect(
      element.shadowRoot.querySelector(".plan-header__name").textContent
    ).toBe("RISK: PolicyTech Adoption Review - Meridian");
    expect(element.shadowRoot.querySelector(".cta-badge").textContent).toBe(
      "Risk"
    );
    expect(element.shadowRoot.querySelector(".cta-badge").className).toContain(
      "cta-badge_risk"
    );
    expect(element.shadowRoot.querySelector(".state-pill").textContent).toBe(
      "In Progress"
    );

    const progress = element.shadowRoot.querySelector('[role="progressbar"]');
    expect(progress.getAttribute("aria-valuenow")).toBe("33");
    expect(progress.getAttribute("aria-label")).toContain("1 of 3 complete");
    expect(
      element.shadowRoot.querySelector(".progress-block__summary").textContent
    ).toBe("1 of 3 complete");
  });

  it("marks completed steps with a strikethrough and a checked box", async () => {
    const element = await renderWith();

    const boxes = checkboxes(element);
    expect(boxes).toHaveLength(2);
    expect(boxes[0].checked).toBe(true);
    expect(boxes[1].checked).toBe(false);
    expect(
      element.shadowRoot.querySelector(".playbook-row__subject_complete")
    ).not.toBeNull();
  });

  it("applies overdue styling only to past due, incomplete steps", async () => {
    const element = await renderWith();

    const overdueRows = element.shadowRoot.querySelectorAll(
      ".playbook-row_overdue"
    );
    expect(overdueRows).toHaveLength(1);
    expect(overdueRows[0].textContent).toContain(
      "3: Generate Configuration Report"
    );
    expect(
      overdueRows[0].querySelector(".playbook-row__overdue-tag").textContent
    ).toBe("Overdue");
  });

  // ------------------------------------------------------- checkbox vs link

  it("gives each checkbox an accessible name of its own now that the row is no longer a label", async () => {
    const element = await renderWith();

    const [completed, open] = checkboxes(element);
    const labels = element.shadowRoot.querySelectorAll(
      "label.slds-assistive-text"
    );

    expect(labels).toHaveLength(2);
    expect(labels[0].getAttribute("for")).toBe(completed.id);
    expect(labels[0].textContent).toBe("Reopen step: 1: Internal Sync");
    expect(labels[1].getAttribute("for")).toBe(open.id);
    expect(labels[1].textContent).toBe(
      "Mark step complete: 3: Generate Configuration Report"
    );
  });

  it("renders the subject as a real anchor pointing at the Task record", async () => {
    const element = await renderWith();

    const links = subjectLinks(element);
    expect(links).toHaveLength(2);
    expect(links[1].getAttribute("href")).toBe(
      `/lightning/r/Task/${OPEN_TASK_ID}/view`
    );
    expect(links[1].title).toBe("Open task: 3: Generate Configuration Report");
    expect(mockGenerateUrl).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: OPEN_TASK_ID,
        objectApiName: "Task",
        actionName: "view"
      }
    });
  });

  it("navigates instead of toggling when the subject link is clicked", async () => {
    const element = await renderWith();

    subjectLinks(element)[1].click();
    await flush();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: OPEN_TASK_ID,
        objectApiName: "Task",
        actionName: "view"
      }
    });
    expect(toggleTaskCompletion).not.toHaveBeenCalled();
    expect(checkboxes(element)[1].checked).toBe(false);
  });

  it("toggles a step from the checkbox and reconciles progress with the server response", async () => {
    const element = await renderWith();

    const serverResponse = playbookFixture({
      completedCount: 2,
      percentComplete: 67
    });
    serverResponse.items[1].isComplete = true;
    serverResponse.items[1].isOverdue = false;
    toggleTaskCompletion.mockResolvedValue(serverResponse);

    const checkbox = checkboxes(element)[1];
    checkbox.checked = true;
    checkbox.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();

    expect(toggleTaskCompletion).toHaveBeenCalledWith({
      recordId: RECORD_ID,
      taskId: OPEN_TASK_ID,
      markComplete: true
    });
    expect(
      element.shadowRoot.querySelector(".progress-block__summary").textContent
    ).toBe("2 of 3 complete");
    expect(
      element.shadowRoot
        .querySelector('[role="progressbar"]')
        .getAttribute("aria-valuenow")
    ).toBe("67");
    expect(
      element.shadowRoot.querySelectorAll(".playbook-row_overdue")
    ).toHaveLength(0);
  });

  it("rolls back the optimistic update and warns the user when the save fails", async () => {
    const element = await renderWith();

    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);
    toggleTaskCompletion.mockRejectedValue({
      body: { message: "Insufficient access" }
    });

    const checkbox = checkboxes(element)[1];
    checkbox.checked = true;
    checkbox.dispatchEvent(new CustomEvent("change"));
    await flush();
    await flush();

    expect(
      element.shadowRoot.querySelector(".progress-block__summary").textContent
    ).toBe("1 of 3 complete");
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "Insufficient access"
    );
  });

  it("disables the checkboxes when the user cannot edit tasks", async () => {
    const element = await renderWith(playbookFixture({ canEditTasks: false }));

    expect(checkboxes(element)[0].disabled).toBe(true);
    expect(element.shadowRoot.querySelector(".read-only-note")).not.toBeNull();
  });

  // ------------------------------------------------------------ waiting rows

  it("renders waiting steps as locked plain text with no link and a disabled menu", async () => {
    const element = await renderWith();

    const waitingRow = element.shadowRoot.querySelector(
      ".playbook-row_waiting"
    );
    expect(waitingRow).not.toBeNull();
    expect(waitingRow.querySelector('input[type="checkbox"]')).toBeNull();
    expect(waitingRow.querySelector("a")).toBeNull();
    expect(
      waitingRow.querySelector("span.playbook-row__subject").textContent
    ).toBe("2: Customer Discovery");
    expect(waitingRow.querySelector(".playbook-row__lock").title).toBe(
      "Waiting on a previous step"
    );
    expect(waitingRow.textContent).toContain("Waiting on a previous step");

    const menu = waitingRow.querySelector("lightning-button-menu");
    expect(menu.disabled).toBe(true);
    expect(menu.querySelectorAll("lightning-menu-item")).toHaveLength(0);
  });

  // -------------------------------------------------------------- row menu

  it("offers edit, open and a state-aware completion action on each live row", async () => {
    const element = await renderWith();

    const [completedMenu, openMenu] = rowMenus(element);
    expect(completedMenu.alternativeText).toBe(
      "Actions for step: 1: Internal Sync"
    );

    const openLabels = Array.from(
      openMenu.querySelectorAll("lightning-menu-item")
    ).map((node) => node.label);
    expect(openLabels).toEqual(["Edit", "Open Task", "Mark Complete"]);

    const completedLabels = Array.from(
      completedMenu.querySelectorAll("lightning-menu-item")
    ).map((node) => node.label);
    expect(completedLabels).toEqual(["Edit", "Open Task", "Reopen"]);
  });

  it("navigates to the Task from the Open Task menu action", async () => {
    const element = await renderWith();

    rowMenus(element)[1].dispatchEvent(
      new CustomEvent("select", { detail: { value: "open" } })
    );
    await flush();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: "standard__recordPage",
      attributes: {
        recordId: OPEN_TASK_ID,
        objectApiName: "Task",
        actionName: "view"
      }
    });
  });

  it("completes a step from the menu exactly as the checkbox does", async () => {
    const element = await renderWith();
    toggleTaskCompletion.mockResolvedValue(
      playbookFixture({ completedCount: 2, percentComplete: 67 })
    );

    rowMenus(element)[1].dispatchEvent(
      new CustomEvent("select", { detail: { value: "toggle" } })
    );
    await flush();
    await flush();

    expect(toggleTaskCompletion).toHaveBeenCalledWith({
      recordId: RECORD_ID,
      taskId: OPEN_TASK_ID,
      markComplete: true
    });
  });

  it("only offers Delete on ad-hoc steps the user added", async () => {
    const fixture = playbookFixture();
    fixture.items.push(adHocItem());
    fixture.totalCount = 4;
    const element = await renderWith(fixture);

    const menus = rowMenus(element);
    const templateLabels = Array.from(
      menus[1].querySelectorAll("lightning-menu-item")
    ).map((n) => n.label);
    const adHocLabels = Array.from(
      menus[3].querySelectorAll("lightning-menu-item")
    ).map((n) => n.label);

    expect(templateLabels).not.toContain("Delete");
    expect(adHocLabels).toContain("Delete");
    expect(element.shadowRoot.querySelector(".adhoc-pill").textContent).toBe(
      "Added"
    );
  });

  it("hides Delete when the user cannot delete plan items", async () => {
    const fixture = playbookFixture({ canDeleteAdHocSteps: false });
    fixture.items.push(adHocItem());
    const element = await renderWith(fixture);

    const adHocLabels = Array.from(
      rowMenus(element)[3].querySelectorAll("lightning-menu-item")
    ).map((n) => n.label);
    expect(adHocLabels).not.toContain("Delete");
  });

  it("deletes an ad-hoc step only after the user confirms", async () => {
    const fixture = playbookFixture();
    fixture.items.push(adHocItem());
    const element = await renderWith(fixture);

    rowMenus(element)[3].dispatchEvent(
      new CustomEvent("select", { detail: { value: "delete" } })
    );
    await flush();
    await flush();
    expect(deleteAdHocStep).not.toHaveBeenCalled();

    LightningConfirm.open.mockResolvedValue(true);
    deleteAdHocStep.mockResolvedValue(playbookFixture());

    rowMenus(element)[3].dispatchEvent(
      new CustomEvent("select", { detail: { value: "delete" } })
    );
    await flush();
    await flush();
    await flush();

    expect(deleteAdHocStep).toHaveBeenCalledWith({
      recordId: RECORD_ID,
      itemId: "07sHs000000AdHoc1"
    });
    expect(element.shadowRoot.querySelectorAll(".playbook-row")).toHaveLength(
      3
    );
  });

  // ----------------------------------------------------------------- modal

  it("opens the edit modal for the row without leaving the page", async () => {
    const element = await renderWith();

    rowMenus(element)[1].dispatchEvent(
      new CustomEvent("select", { detail: { value: "edit" } })
    );
    await flush();

    expect(NavexTaskModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        size: "small",
        label: "Edit Step",
        taskId: OPEN_TASK_ID,
        defaultWhatId: ACCOUNT_ID
      })
    );
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it("refreshes the list and confirms with a toast after an edit is saved", async () => {
    const { refreshApex } = require("@salesforce/apex");
    const element = await renderWith();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    NavexTaskModal.open.mockResolvedValue({
      status: "saved",
      recordId: OPEN_TASK_ID,
      isCreate: false
    });

    rowMenus(element)[1].dispatchEvent(
      new CustomEvent("select", { detail: { value: "edit" } })
    );
    await flush();
    await flush();
    await flush();

    expect(refreshApex).toHaveBeenCalled();
    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("success");
    expect(toastHandler.mock.calls[0][0].detail.title).toBe("Step updated");
  });

  it("leaves the playbook untouched when the modal is cancelled", async () => {
    const element = await renderWith();

    rowMenus(element)[1].dispatchEvent(
      new CustomEvent("select", { detail: { value: "edit" } })
    );
    await flush();
    await flush();

    expect(addAdHocStep).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector(".progress-block__summary").textContent
    ).toBe("1 of 3 complete");
  });

  it("returns focus to the menu that opened the modal", async () => {
    const element = await renderWith();
    const menu = rowMenus(element)[1];
    const focusSpy = jest.spyOn(menu, "focus");

    menu.dispatchEvent(
      new CustomEvent("select", { detail: { value: "edit" } })
    );
    await flush();
    await flush();

    expect(focusSpy).toHaveBeenCalled();
  });

  // -------------------------------------------------------------- new step

  it("adds an ad-hoc step and counts it in progress", async () => {
    const element = await renderWith();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    NavexTaskModal.open.mockResolvedValue({
      status: "saved",
      recordId: "00THs0000EDfvzWMQR",
      isCreate: true
    });

    const withNewStep = playbookFixture({ totalCount: 4, percentComplete: 25 });
    withNewStep.items.push(adHocItem());
    addAdHocStep.mockResolvedValue(withNewStep);

    const newStepButton =
      element.shadowRoot.querySelector(".card-actions__new");
    newStepButton.click();
    await flush();
    await flush();
    await flush();

    expect(NavexTaskModal.open).toHaveBeenCalledWith(
      expect.objectContaining({
        label: "New Step",
        taskId: undefined,
        defaultWhatId: ACCOUNT_ID
      })
    );
    expect(addAdHocStep).toHaveBeenCalledWith({
      recordId: RECORD_ID,
      taskId: "00THs0000EDfvzWMQR"
    });
    expect(element.shadowRoot.querySelectorAll(".playbook-row")).toHaveLength(
      4
    );
    expect(
      element.shadowRoot.querySelector(".progress-block__summary").textContent
    ).toBe("1 of 4 complete");
    expect(toastHandler.mock.calls[0][0].detail.title).toBe("Step added");
  });

  it("surfaces a failure to link the new step without dropping the existing list", async () => {
    const element = await renderWith();
    const toastHandler = jest.fn();
    element.addEventListener("lightning__showtoast", toastHandler);

    NavexTaskModal.open.mockResolvedValue({
      status: "saved",
      recordId: "00THs0000EDfvzWMQR",
      isCreate: true
    });
    addAdHocStep.mockRejectedValue({
      body: { message: "That task is already a step on an action plan." }
    });

    element.shadowRoot.querySelector(".card-actions__new").click();
    await flush();
    await flush();
    await flush();

    expect(toastHandler.mock.calls[0][0].detail.variant).toBe("error");
    expect(toastHandler.mock.calls[0][0].detail.message).toBe(
      "That task is already a step on an action plan."
    );
    expect(element.shadowRoot.querySelectorAll(".playbook-row")).toHaveLength(
      3
    );
  });

  it("hides the New Step button when the user cannot create plan items", async () => {
    const element = await renderWith(
      playbookFixture({ canCreateSteps: false })
    );
    expect(element.shadowRoot.querySelector(".card-actions__new")).toBeNull();
  });

  // ------------------------------------------------------- guidance, states

  it("shows the guidance panel from the template description and expands it on click", async () => {
    const element = await renderWith();

    const toggle = element.shadowRoot.querySelector(".guidance__toggle");
    expect(toggle.getAttribute("aria-expanded")).toBe("false");
    expect(element.shadowRoot.querySelector(".guidance__body")).toBeNull();

    toggle.click();
    await flush();

    expect(toggle.getAttribute("aria-expanded")).toBe("true");
    expect(element.shadowRoot.querySelector(".guidance__body")).not.toBeNull();
  });

  it("prefers the App Builder guidance text over the template description", async () => {
    const element = await renderWith(playbookFixture(), {
      guidanceText: "Admin supplied guidance",
      expandGuidance: true
    });

    const body = element.shadowRoot.querySelector(
      ".guidance__body lightning-formatted-text"
    );
    expect(body.value).toBe("Admin supplied guidance");
  });

  it("shows an empty state when the plan has no steps", async () => {
    const element = await renderWith(
      playbookFixture({
        items: [],
        totalCount: 0,
        completedCount: 0,
        percentComplete: 0
      })
    );

    expect(element.shadowRoot.querySelector(".playbook-list")).toBeNull();
    const empty = element.shadowRoot.querySelector(".empty-state");
    expect(empty.getAttribute("role")).toBe("status");
    expect(empty.textContent).toContain("No steps yet");
  });

  it("shows a readable error state when the playbook cannot be loaded", async () => {
    const element = createComponent();
    getPlaybook.error({ message: "You do not have access." }, 403, "Forbidden");
    await flush();

    const error = element.shadowRoot.querySelector(".error-boundary");
    expect(error.getAttribute("role")).toBe("alert");
    expect(error.textContent).toContain("You do not have access.");
    expect(element.shadowRoot.querySelector(".playbook-list")).toBeNull();
  });
});
