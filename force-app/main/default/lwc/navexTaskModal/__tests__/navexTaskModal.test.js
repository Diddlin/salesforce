import { createElement } from "lwc";
import NavexTaskModal from "c/navexTaskModal";

const TASK_ID = "00THs0000EDfvnTMQR";
const ACCOUNT_ID = "001Hs00005wLdgKIAS";

function createModal(props = {}) {
  const element = createElement("c-navex-task-modal", { is: NavexTaskModal });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

const flush = () => Promise.resolve();
const form = (element) =>
  element.shadowRoot.querySelector("lightning-record-edit-form");
const footerButtons = (element) =>
  element.shadowRoot.querySelectorAll("lightning-button");
const fieldNames = (element) =>
  Array.from(element.shadowRoot.querySelectorAll("lightning-input-field")).map(
    (node) => node.fieldName
  );

describe("c-navex-task-modal", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("edits an existing task with the expected fields bound to the record", async () => {
    const element = createModal({ taskId: TASK_ID });
    await flush();

    expect(form(element).objectApiName).toBe("Task");
    expect(form(element).recordId).toBe(TASK_ID);
    expect(fieldNames(element)).toEqual([
      "Subject",
      "Status",
      "Priority",
      "ActivityDate",
      "OwnerId",
      "Description"
    ]);
    expect(footerButtons(element)[1].label).toBe("Save");
  });

  it("creates a task prefilled with the plan target so it lands on that record timeline", async () => {
    const element = createModal({ defaultWhatId: ACCOUNT_ID });
    await flush();

    expect(form(element).recordId).toBeUndefined();
    expect(fieldNames(element)).toContain("WhatId");

    const whatField = Array.from(
      element.shadowRoot.querySelectorAll("lightning-input-field")
    ).find((node) => node.fieldName === "WhatId");
    expect(whatField.value).toBe(ACCOUNT_ID);
    expect(footerButtons(element)[1].label).toBe("Create Step");
  });

  it("omits the related-to field when the plan target cannot be a task relation", async () => {
    const element = createModal({});
    await flush();

    expect(fieldNames(element)).not.toContain("WhatId");
  });

  it("submits the form when Save is pressed", async () => {
    const element = createModal({ taskId: TASK_ID });
    await flush();

    const submit = jest.fn();
    form(element).submit = submit;
    footerButtons(element)[1].click();
    await flush();

    expect(submit).toHaveBeenCalled();
  });

  it("closes with the saved record id once the UI API confirms the write", async () => {
    const element = createModal({ taskId: TASK_ID });
    await flush();

    const closeHandler = jest.fn();
    element.addEventListener("close", closeHandler);

    form(element).dispatchEvent(
      new CustomEvent("success", { detail: { id: TASK_ID } })
    );
    await flush();

    expect(closeHandler).toHaveBeenCalled();
    expect(closeHandler.mock.calls[0][0].detail).toEqual({
      status: "saved",
      recordId: TASK_ID,
      isCreate: false
    });
  });

  it("closes as cancelled without saving when Cancel is pressed", async () => {
    const element = createModal({ taskId: TASK_ID });
    await flush();

    const closeHandler = jest.fn();
    element.addEventListener("close", closeHandler);

    footerButtons(element)[0].click();
    await flush();

    expect(closeHandler.mock.calls[0][0].detail).toEqual({
      status: "cancelled"
    });
  });

  it("stays open and shows the error inline when the save is rejected", async () => {
    const element = createModal({ taskId: TASK_ID });
    await flush();

    const closeHandler = jest.fn();
    element.addEventListener("close", closeHandler);

    form(element).dispatchEvent(
      new CustomEvent("error", {
        detail: { detail: "Subject: bad value for restricted picklist" }
      })
    );
    await flush();

    expect(closeHandler).not.toHaveBeenCalled();
    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain(
      "Subject: bad value for restricted picklist"
    );
    expect(form(element)).not.toBeNull();
  });

  it("falls back to a generic message when the error payload has no detail", async () => {
    const element = createModal({ taskId: TASK_ID });
    await flush();

    form(element).dispatchEvent(new CustomEvent("error", { detail: {} }));
    await flush();

    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("The task could not be saved.");
  });
});
