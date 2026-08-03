import { LightningElement, api, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { refreshApex } from "@salesforce/apex";
import getTimeline from "@salesforce/apex/NavexCxTimelineController.getTimeline";
import { resolveCategory } from "./milestoneCategory";

const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
];

const NODE_SELECTOR = ".cx-node__button";

/**
 * Dates arrive from Apex as plain "YYYY-MM-DD" strings. Splitting them by hand keeps the label
 * on the date the CSM actually recorded: passing the string to Date() parses it as UTC midnight,
 * which renders as the previous day for anyone west of Greenwich.
 */
function parseIsoDate(value) {
  if (typeof value !== "string") {
    return undefined;
  }
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  if (!match) {
    return undefined;
  }
  const [, year, month, day] = match;
  return {
    year: Number(year),
    monthIndex: Number(month) - 1,
    day: Number(day)
  };
}

function shortDateLabel(value) {
  const parts = parseIsoDate(value);
  if (!parts) {
    return "No date";
  }
  return `${MONTHS[parts.monthIndex]} '${String(parts.year).slice(-2)}`;
}

function fullDateLabel(value) {
  const parts = parseIsoDate(value);
  if (!parts) {
    return "No date recorded";
  }
  return `${parts.day} ${MONTHS[parts.monthIndex]} ${parts.year}`;
}

export default class NavexCxTimeline extends NavigationMixin(LightningElement) {
  @api recordId;
  @api cardTitle = "Customer Lifecycle";
  @api maxMilestones = 20;
  @api includeFuture = false;
  @api milestonesOnly = false;
  @api emptyMessage =
    "No lifecycle milestones yet. Logged calls, emails and meetings on this account will appear here.";

  timeline;
  errorMessage;
  isLoading = true;
  selectedId;

  recordUrls = {};

  _wiredResult;
  _scrollToSelected = false;

  @wire(getTimeline, {
    recordId: "$recordId",
    maxMilestones: "$maxMilestonesValue",
    includeFuture: "$includeFutureValue",
    milestonesOnly: "$milestonesOnlyValue"
  })
  wiredTimeline(result) {
    this._wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.timeline = data;
      this.errorMessage = undefined;
      this.isLoading = false;
      // A milestone that has dropped out of the refreshed data must not leave the panel open
      // showing content the server no longer returns.
      if (
        this.selectedId &&
        !data.milestones.some((item) => item.recordId === this.selectedId)
      ) {
        this.selectedId = undefined;
      }
      this.resolveRecordUrls(data.milestones);
    } else if (error) {
      this.timeline = undefined;
      this.selectedId = undefined;
      this.errorMessage = this.readableError(error);
      this.isLoading = false;
    }
  }

  /** App Builder hands numbers back as strings, and an empty box comes through as "". */
  get maxMilestonesValue() {
    const parsed = parseInt(this.maxMilestones, 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 20;
  }

  get includeFutureValue() {
    return this.includeFuture === true || this.includeFuture === "true";
  }

  get milestonesOnlyValue() {
    return this.milestonesOnly === true || this.milestonesOnly === "true";
  }

  /**
   * Real hrefs let a milestone be middle-clicked or opened in a new tab. Until GenerateUrl
   * resolves, the view model falls back to the standard record URL so the link is never
   * rendered without an href, which would drop it out of the tab order.
   */
  resolveRecordUrls(milestones) {
    const pending = (milestones || [])
      .filter((item) => item.recordId && !this.recordUrls[item.recordId])
      .map((item) =>
        this[NavigationMixin.GenerateUrl]({
          type: "standard__recordPage",
          attributes: {
            recordId: item.recordId,
            objectApiName: item.objectApiName,
            actionName: "view"
          }
        }).then((url) => ({ recordId: item.recordId, url }))
      );
    if (!pending.length) {
      return;
    }
    Promise.all(pending)
      .then((resolved) => {
        const next = { ...this.recordUrls };
        resolved.forEach(({ recordId, url }) => {
          if (url) {
            next[recordId] = url;
          }
        });
        this.recordUrls = next;
      })
      .catch(() => {
        // The fallback URL already covers this; nothing to tell the user.
      });
  }

  // ------------------------------------------------------------ header

  get milestones() {
    if (!this.timeline || !this.timeline.milestones) {
      return [];
    }
    return this.timeline.milestones.map((item) => this.toViewModel(item));
  }

  get hasMilestones() {
    return this.milestones.length > 0;
  }

  get milestoneCount() {
    return this.timeline ? this.timeline.totalCount : 0;
  }

  get countLabel() {
    const count = this.milestoneCount;
    return `${count} ${count === 1 ? "milestone" : "milestones"}`;
  }

  get truncationNote() {
    if (!this.timeline || !this.timeline.isTruncated) {
      return undefined;
    }
    return `Showing the ${this.timeline.totalCount} most recent of ${this.timeline.availableCount} activities.`;
  }

  get hasTruncationNote() {
    return !!this.truncationNote;
  }

  get showTimeline() {
    return !this.isLoading && !this.errorMessage && this.hasMilestones;
  }

  get showEmptyState() {
    return (
      !this.isLoading &&
      !this.errorMessage &&
      !!this.timeline &&
      !this.hasMilestones
    );
  }

  // ------------------------------------------------------------ nodes

  toViewModel(milestone) {
    const category = resolveCategory(milestone);
    const isSelected = milestone.recordId === this.selectedId;
    const dateLabel = shortDateLabel(milestone.activityDate);

    const markerClasses = ["cx-node__marker", `cx-marker_${category.key}`];
    if (milestone.isFuture) {
      markerClasses.push("cx-node__marker_future");
    }
    if (isSelected) {
      markerClasses.push("cx-node__marker_selected");
    }

    const buttonClasses = ["cx-node__button"];
    if (isSelected) {
      buttonClasses.push("cx-node__button_selected");
    }
    if (milestone.isFuture) {
      buttonClasses.push("cx-node__button_future");
    }

    return {
      ...milestone,
      key: milestone.recordId,
      categoryKey: category.key,
      categoryLabel: category.label,
      iconName: category.iconName,
      dateLabel,
      fullDateLabel: fullDateLabel(milestone.activityDate),
      markerClass: markerClasses.join(" "),
      buttonClass: buttonClasses.join(" "),
      isSelected,
      // Spoken as "Mar '26, Adoption alert, Risk, upcoming" so the node makes sense on its own.
      ariaLabel: [
        dateLabel,
        milestone.subject,
        category.label,
        milestone.isFuture ? "upcoming" : undefined
      ]
        .filter(Boolean)
        .join(", ")
    };
  }

  get selectedMilestone() {
    if (!this.selectedId) {
      return undefined;
    }
    const found = this.milestones.find((item) => item.isSelected);
    if (!found) {
      return undefined;
    }
    return {
      ...found,
      panelClass: `cx-detail cx-detail_${found.categoryKey}`,
      recordUrl:
        this.recordUrls[found.recordId] ||
        `/lightning/r/${found.objectApiName}/${found.recordId}/view`,
      openLabel: `Open this ${found.objectApiName === "Event" ? "event" : "task"}`,
      hasDescription: !!found.description,
      statusLabel: found.isFuture
        ? "Upcoming"
        : found.status || (found.isCompleted ? "Completed" : undefined)
    };
  }

  get hasSelection() {
    return !!this.selectedMilestone;
  }

  // ------------------------------------------------------------ handlers

  handleNodeClick(event) {
    const { recordId } = event.currentTarget.dataset;
    this.selectedId = this.selectedId === recordId ? undefined : recordId;
    this._scrollToSelected = !!this.selectedId;
  }

  handleDismiss() {
    const previous = this.selectedId;
    this.selectedId = undefined;
    // Focus goes back to the node that opened the panel, so keyboard users are not dumped at
    // the top of the page.
    Promise.resolve().then(() => {
      const node = this.template.querySelector(
        `${NODE_SELECTOR}[data-record-id="${previous}"]`
      );
      if (node) {
        node.focus();
      }
    });
  }

  /** Arrow keys walk the row, which is faster than tabbing through every node. */
  handleTrackKeydown(event) {
    const keys = ["ArrowRight", "ArrowLeft", "Home", "End"];
    if (!keys.includes(event.key)) {
      return;
    }
    const nodes = Array.from(this.template.querySelectorAll(NODE_SELECTOR));
    if (!nodes.length) {
      return;
    }
    const current = nodes.indexOf(event.target.closest(NODE_SELECTOR));
    if (current < 0) {
      return;
    }
    event.preventDefault();

    let next = current;
    if (event.key === "ArrowRight") {
      next = Math.min(current + 1, nodes.length - 1);
    } else if (event.key === "ArrowLeft") {
      next = Math.max(current - 1, 0);
    } else if (event.key === "Home") {
      next = 0;
    } else {
      next = nodes.length - 1;
    }
    nodes[next].focus();
  }

  /** The panel link is a real anchor; this only upgrades it to client-side navigation. */
  handleOpenRecord(event) {
    const selected = this.selectedMilestone;
    if (!selected) {
      return;
    }
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: selected.recordId,
        objectApiName: selected.objectApiName,
        actionName: "view"
      }
    });
  }

  handleRefresh() {
    this.isLoading = true;
    this.refresh().finally(() => {
      this.isLoading = false;
    });
  }

  renderedCallback() {
    if (!this._scrollToSelected) {
      return;
    }
    this._scrollToSelected = false;
    const node = this.template.querySelector(
      `${NODE_SELECTOR}[data-record-id="${this.selectedId}"]`
    );
    // jsdom has no layout, so scrollIntoView is absent under test.
    if (node && typeof node.scrollIntoView === "function") {
      node.scrollIntoView({ block: "nearest", inline: "center" });
    }
  }

  // ------------------------------------------------------------ utilities

  refresh() {
    return this._wiredResult
      ? refreshApex(this._wiredResult)
      : Promise.resolve();
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
