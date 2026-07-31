import { api } from "lwc";
import LightningModal from "lightning/modal";

/**
 * Create/edit form for the Task behind a playbook step.
 *
 * The form is a lightning-record-edit-form, so the UI API enforces field-level security, required
 * fields and picklist restrictions without any Apex of our own. The caller receives
 * { status: 'saved', recordId } on save and { status: 'cancelled' } otherwise.
 */
export default class NavexTaskModal extends LightningModal {
  @api taskId;
  @api defaultWhatId;
  @api relatedToLabel = "Related To";

  isSaving = false;
  errorMessage;

  get isCreate() {
    return !this.taskId;
  }

  get showRelatedTo() {
    return this.isCreate && !!this.defaultWhatId;
  }

  get saveLabel() {
    return this.isCreate ? "Create Step" : "Save";
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get form() {
    return this.template.querySelector("lightning-record-edit-form");
  }

  handleSave() {
    this.errorMessage = undefined;
    const form = this.form;
    if (form) {
      form.submit();
    }
  }

  handleSubmit() {
    this.isSaving = true;
  }

  handleSuccess(event) {
    this.isSaving = false;
    this.close({
      status: "saved",
      recordId: event.detail.id,
      isCreate: this.isCreate
    });
  }

  /** Keeps the modal open so the user can correct the record without losing what they typed. */
  handleError(event) {
    this.isSaving = false;
    this.errorMessage = this.readableError(event.detail);
  }

  handleCancel() {
    this.close({ status: "cancelled" });
  }

  readableError(detail) {
    if (!detail) {
      return "The task could not be saved.";
    }
    if (detail.detail) {
      return detail.detail;
    }
    if (detail.message) {
      return detail.message;
    }
    const output = detail.output;
    if (output && Array.isArray(output.errors) && output.errors.length) {
      return output.errors[0].message;
    }
    return "The task could not be saved.";
  }
}
