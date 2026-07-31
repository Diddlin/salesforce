/**
 * Test stub for the lightning/modal base component, which sfdx-lwc-jest does not yet ship.
 * Mirrors the public shape used by our modal subclasses: the static open() and the close()
 * instance method, plus the inherited @api properties supplied through open()'s config.
 */
import { LightningElement, api } from "lwc";

export default class LightningModal extends LightningElement {
  @api size = "medium";
  @api label;
  @api description;
  @api disableClose = false;

  static open() {
    return Promise.resolve();
  }

  @api
  close(result) {
    this.dispatchEvent(new CustomEvent("close", { detail: result }));
  }
}
