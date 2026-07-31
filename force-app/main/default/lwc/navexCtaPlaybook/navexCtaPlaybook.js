import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import { getRecordNotifyChange } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import NavexTaskModal from "c/navexTaskModal";
import getPlaybook from "@salesforce/apex/NavexCtaPlaybookController.getPlaybook";
import toggleTaskCompletion from "@salesforce/apex/NavexCtaPlaybookController.toggleTaskCompletion";
import addAdHocStep from "@salesforce/apex/NavexCtaPlaybookController.addAdHocStep";
import deleteAdHocStep from "@salesforce/apex/NavexCtaPlaybookController.deleteAdHocStep";

const CTA_TYPE_CLASSES = {
  risk: "cta-badge cta-badge_risk",
  lifecycle: "cta-badge cta-badge_lifecycle",
  expansion: "cta-badge cta-badge_expansion"
};
const DEFAULT_CTA_TYPE_CLASS = "cta-badge cta-badge_other";

const ACTION_EDIT = "edit";
const ACTION_OPEN = "open";
const ACTION_TOGGLE = "toggle";
const ACTION_DELETE = "delete";

export default class NavexCtaPlaybook extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @api cardTitle = "Playbook";
  @api guidanceText;
  @api expandGuidance = false;
  @api emptyMessage =
    "This action plan has no steps yet. Steps appear here once the plan is generated from its template.";

  playbook;
  errorMessage;
  isLoading = true;
  isSaving = false;
  guidanceOpen = false;
  liveMessage = "";
  taskUrls = {};

  _wiredResult;
  _guidanceInitialised = false;
  _modalTrigger;

  @wire(getPlaybook, { recordId: "$recordId" })
  wiredPlaybook(result) {
    this._wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.playbook = data;
      this.errorMessage = undefined;
      this.isLoading = false;
      if (!this._guidanceInitialised) {
        this.guidanceOpen = this.expandGuidance === true;
        this._guidanceInitialised = true;
      }
      this.resolveTaskUrls(data.items);
    } else if (error) {
      this.playbook = undefined;
      this.errorMessage = this.readableError(error);
      this.isLoading = false;
    }
  }

  /**
   * Real hrefs let the subject links be middle-clicked, cmd-clicked and opened in a new tab.
   * Until GenerateUrl resolves, toViewModel falls back to the standard record URL so the anchor
   * is never rendered without an href (which would drop it out of the tab order).
   */
  resolveTaskUrls(items) {
    const pending = (items || [])
      .filter((item) => item.taskId && !this.taskUrls[item.taskId])
      .map((item) =>
        this[NavigationMixin.GenerateUrl]({
          type: "standard__recordPage",
          attributes: {
            recordId: item.taskId,
            objectApiName: "Task",
            actionName: "view"
          }
        }).then((url) => ({ taskId: item.taskId, url }))
      );
    if (!pending.length) {
      return;
    }
    Promise.all(pending)
      .then((resolved) => {
        const next = { ...this.taskUrls };
        resolved.forEach(({ taskId, url }) => {
          if (url) {
            next[taskId] = url;
          }
        });
        this.taskUrls = next;
      })
      .catch(() => {
        // The fallback URL already covers this; no user-facing failure needed.
      });
  }

  // ------------------------------------------------------------ header

  get planName() {
    return this.playbook ? this.playbook.planName : "";
  }

  get hasPlan() {
    return !!this.playbook;
  }

  get ctaType() {
    return this.playbook ? this.playbook.ctaType : undefined;
  }

  get hasCtaType() {
    return !!this.ctaType;
  }

  get ctaTypeClass() {
    const key = this.ctaType ? this.ctaType.toLowerCase() : "";
    return CTA_TYPE_CLASSES[key] || DEFAULT_CTA_TYPE_CLASS;
  }

  get planState() {
    return this.playbook ? this.playbook.state : undefined;
  }

  get hasPlanState() {
    return !!this.planState;
  }

  get startDate() {
    return this.playbook ? this.playbook.startDate : undefined;
  }

  get endDate() {
    return this.playbook ? this.playbook.endDate : undefined;
  }

  get hasStartDate() {
    return !!this.startDate;
  }

  get hasEndDate() {
    return !!this.endDate;
  }

  get canCreateSteps() {
    return !!this.playbook && this.playbook.canCreateSteps === true;
  }

  get newStepDisabled() {
    return this.isSaving || this.isLoading;
  }

  // ------------------------------------------------------------ progress

  get percentComplete() {
    return this.playbook ? this.playbook.percentComplete : 0;
  }

  get completedCount() {
    return this.playbook ? this.playbook.completedCount : 0;
  }

  get totalCount() {
    return this.playbook ? this.playbook.totalCount : 0;
  }

  get progressStyle() {
    return `width: ${this.percentComplete}%`;
  }

  get progressFillClass() {
    if (this.percentComplete >= 100) {
      return "progress__fill progress__fill_complete";
    }
    if (this.percentComplete > 0) {
      return "progress__fill progress__fill_partial";
    }
    return "progress__fill";
  }

  get progressSummary() {
    return `${this.completedCount} of ${this.totalCount} complete`;
  }

  get progressLabel() {
    return `Playbook progress: ${this.progressSummary}, ${this.percentComplete} percent`;
  }

  // ------------------------------------------------------------ guidance

  get guidance() {
    if (this.guidanceText && this.guidanceText.trim()) {
      return this.guidanceText;
    }
    return this.playbook ? this.playbook.templateGuidance : undefined;
  }

  get hasGuidance() {
    return !!this.guidance;
  }

  get guidanceIcon() {
    return this.guidanceOpen ? "utility:chevrondown" : "utility:chevronright";
  }

  // ------------------------------------------------------------ items

  get items() {
    if (!this.playbook || !this.playbook.items) {
      return [];
    }
    return this.playbook.items.map((item) => this.toViewModel(item));
  }

  get hasItems() {
    return this.items.length > 0;
  }

  get showEmptyState() {
    return (
      !this.isLoading && !this.errorMessage && this.hasPlan && !this.hasItems
    );
  }

  get showChecklist() {
    return !this.isLoading && !this.errorMessage && this.hasItems;
  }

  toViewModel(item) {
    const classes = ["playbook-row"];
    if (item.isWaiting) {
      classes.push("playbook-row_waiting");
    }
    if (item.isComplete) {
      classes.push("playbook-row_complete");
    }
    if (item.isOverdue) {
      classes.push("playbook-row_overdue");
    }

    const ownerName = item.ownerName || "";
    const toggleLabel = item.isComplete
      ? `Reopen step: ${item.subject}`
      : `Mark step complete: ${item.subject}`;

    return {
      ...item,
      key: item.itemId,
      rowClass: classes.join(" "),
      checkboxId: `step-${item.itemId}`,
      checkboxLabel: toggleLabel,
      subjectClass: item.isComplete
        ? "playbook-row__subject playbook-row__subject_complete"
        : "playbook-row__subject",
      taskUrl: item.taskId
        ? this.taskUrls[item.taskId] || `/lightning/r/Task/${item.taskId}/view`
        : undefined,
      subjectTitle: item.taskId ? `Open task: ${item.subject}` : undefined,
      dueDateClass: item.isOverdue
        ? "playbook-row__due playbook-row__due_overdue"
        : "playbook-row__due",
      hasDueDate: !!item.dueDate && !item.isWaiting,
      hasOwner: !!ownerName && !item.isWaiting,
      ownerInitials: this.initialsFor(ownerName),
      isHighPriority: item.priority === "High",
      statusText: this.statusTextFor(item),
      toggleDisabled: !this.canEdit || this.isSaving,
      menuLabel: `Actions for step: ${item.subject}`,
      menuDisabled: item.isWaiting || this.isSaving,
      menuActions: this.menuActionsFor(item)
    };
  }

  menuActionsFor(item) {
    if (item.isWaiting) {
      // Nothing is actionable until the prerequisite closes and the Task is created.
      return [];
    }
    const actions = [
      { value: ACTION_EDIT, label: "Edit", iconName: "utility:edit" },
      {
        value: ACTION_OPEN,
        label: "Open Task",
        iconName: "utility:new_window"
      },
      {
        value: ACTION_TOGGLE,
        label: item.isComplete ? "Reopen" : "Mark Complete",
        iconName: item.isComplete ? "utility:undo" : "utility:check"
      }
    ];
    if (item.isAdHoc && this.canDeleteAdHoc) {
      actions.push({
        value: ACTION_DELETE,
        label: "Delete",
        iconName: "utility:delete"
      });
    }
    return actions;
  }

  initialsFor(name) {
    if (!name) {
      return "";
    }
    return name
      .split(/\s+/)
      .filter((part) => part.length > 0)
      .slice(0, 2)
      .map((part) => part.charAt(0).toUpperCase())
      .join("");
  }

  statusTextFor(item) {
    if (item.isWaiting) {
      return "Waiting on a previous step";
    }
    if (item.isComplete) {
      return "Complete";
    }
    if (item.isOverdue) {
      return "Overdue";
    }
    return item.status || "Open";
  }

  get canEdit() {
    return !!this.playbook && this.playbook.canEditTasks === true;
  }

  get canDeleteAdHoc() {
    return !!this.playbook && this.playbook.canDeleteAdHocSteps === true;
  }

  get isReadOnly() {
    return this.hasPlan && !this.canEdit;
  }

  // ------------------------------------------------------------ handlers

  handleGuidanceToggle() {
    this.guidanceOpen = !this.guidanceOpen;
  }

  handleRefresh() {
    this.isLoading = true;
    this.refresh().finally(() => {
      this.isLoading = false;
    });
  }

  handleToggle(event) {
    const { taskId, itemId } = event.target.dataset;
    return this.toggleStep(itemId, taskId, event.target.checked);
  }

  /** The subject is a real link; this only upgrades it to client-side navigation. */
  handleSubjectClick(event) {
    const { taskId } = event.currentTarget.dataset;
    if (!taskId) {
      return;
    }
    event.preventDefault();
    this.navigateToTask(taskId);
  }

  handleRowAction(event) {
    const action = event.detail.value;
    const { itemId, taskId } = event.target.dataset;
    const item = this.findItem(itemId);
    if (!item) {
      return;
    }
    this._modalTrigger = event.target;

    switch (action) {
      case ACTION_OPEN:
        this.navigateToTask(taskId);
        break;
      case ACTION_TOGGLE:
        this.toggleStep(itemId, taskId, !item.isComplete);
        break;
      case ACTION_EDIT:
        this.openTaskModal({ taskId, label: "Edit Step" });
        break;
      case ACTION_DELETE:
        this.confirmDelete(item);
        break;
      default:
        break;
    }
  }

  handleNewStep(event) {
    this._modalTrigger = event.target;
    this.openTaskModal({ taskId: undefined, label: "New Step" });
  }

  findItem(itemId) {
    if (!this.playbook || !this.playbook.items) {
      return undefined;
    }
    return this.playbook.items.find((candidate) => candidate.itemId === itemId);
  }

  navigateToTask(taskId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: taskId,
        objectApiName: "Task",
        actionName: "view"
      }
    });
  }

  // ------------------------------------------------------------ toggling

  async toggleStep(itemId, taskId, markComplete) {
    if (!taskId || this.isSaving || !this.canEdit) {
      return;
    }

    const snapshot = this.playbook;
    this.isSaving = true;
    this.playbook = this.applyOptimisticToggle(snapshot, itemId, markComplete);
    this.liveMessage = `${this.progressSummary}. Saving…`;

    try {
      const updated = await toggleTaskCompletion({
        recordId: this.recordId,
        taskId,
        markComplete
      });
      this.playbook = updated;
      this.errorMessage = undefined;
      this.liveMessage = this.progressSummary;
      getRecordNotifyChange([
        { recordId: taskId },
        { recordId: this.recordId }
      ]);
      this.refresh();
      this.showToast(
        markComplete ? "Step completed" : "Step reopened",
        `${this.progressSummary} on ${this.planName}.`,
        "success"
      );
    } catch (error) {
      this.playbook = snapshot;
      this.liveMessage = "The step could not be updated.";
      this.showToast(
        "Could not update step",
        this.readableError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
    }
  }

  /**
   * Recomputes counts locally so the checkbox and the progress bar move together on click,
   * before the round trip finishes. The server response replaces this shortly after.
   */
  applyOptimisticToggle(playbook, itemId, markComplete) {
    const items = playbook.items.map((item) => {
      if (item.itemId !== itemId) {
        return item;
      }
      return {
        ...item,
        isComplete: markComplete,
        isOverdue: markComplete ? false : item.isOverdue
      };
    });
    const completedCount = items.filter((item) => item.isComplete).length;
    const totalCount = items.length;
    return {
      ...playbook,
      items,
      completedCount,
      totalCount,
      percentComplete:
        totalCount === 0 ? 0 : Math.round((100 * completedCount) / totalCount)
    };
  }

  // ------------------------------------------------------------ modal

  async openTaskModal({ taskId, label }) {
    const isCreate = !taskId;
    let result;
    try {
      result = await NavexTaskModal.open({
        size: "small",
        label,
        description: isCreate
          ? "Create a new step on this action plan"
          : "Edit the task behind this playbook step",
        taskId,
        defaultWhatId: this.playbook ? this.playbook.relatedToId : undefined
      });
    } catch (error) {
      this.showToast(
        "Could not open the step",
        this.readableError(error),
        "error"
      );
      this.restoreModalFocus();
      return;
    }

    if (!result || result.status !== "saved") {
      this.restoreModalFocus();
      return;
    }

    if (isCreate) {
      await this.linkNewStep(result.recordId);
    } else {
      getRecordNotifyChange([{ recordId: result.recordId }]);
      await this.refresh();
      this.liveMessage = this.progressSummary;
      this.showToast(
        "Step updated",
        "Your changes have been saved.",
        "success"
      );
    }
    this.restoreModalFocus();
  }

  async linkNewStep(taskId) {
    this.isSaving = true;
    try {
      this.playbook = await addAdHocStep({ recordId: this.recordId, taskId });
      this.resolveTaskUrls(this.playbook.items);
      this.errorMessage = undefined;
      this.liveMessage = this.progressSummary;
      getRecordNotifyChange([{ recordId: this.recordId }]);
      this.refresh();
      this.showToast(
        "Step added",
        `${this.progressSummary} on ${this.planName}.`,
        "success"
      );
    } catch (error) {
      this.showToast("Could not add step", this.readableError(error), "error");
    } finally {
      this.isSaving = false;
    }
  }

  /**
   * LightningModal returns focus to whatever was focused when it opened, but doing it explicitly
   * keeps the behaviour deterministic for the toast and error paths too.
   */
  restoreModalFocus() {
    const trigger = this._modalTrigger;
    this._modalTrigger = undefined;
    if (trigger && typeof trigger.focus === "function") {
      trigger.focus();
    }
  }

  // ------------------------------------------------------------ delete

  async confirmDelete(item) {
    const confirmed = await LightningConfirm.open({
      label: "Remove step",
      message: `Remove "${item.subject}" from this playbook? The task will be deleted.`,
      theme: "warning",
      variant: "header"
    });
    if (!confirmed) {
      this.restoreModalFocus();
      return;
    }

    this.isSaving = true;
    try {
      this.playbook = await deleteAdHocStep({
        recordId: this.recordId,
        itemId: item.itemId
      });
      this.errorMessage = undefined;
      this.liveMessage = this.progressSummary;
      getRecordNotifyChange([{ recordId: this.recordId }]);
      this.refresh();
      this.showToast(
        "Step removed",
        `${this.progressSummary} on ${this.planName}.`,
        "success"
      );
    } catch (error) {
      this.showToast(
        "Could not remove step",
        this.readableError(error),
        "error"
      );
    } finally {
      this.isSaving = false;
      this.restoreModalFocus();
    }
  }

  // ------------------------------------------------------------ utilities

  refresh() {
    return this._wiredResult
      ? refreshApex(this._wiredResult)
      : Promise.resolve();
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  readableError(error) {
    if (!error) {
      return "An unexpected error occurred.";
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    if (
      Array.isArray(error.body) &&
      error.body.length &&
      error.body[0].message
    ) {
      return error.body[0].message;
    }
    if (error.message) {
      return error.message;
    }
    return "An unexpected error occurred.";
  }
}
