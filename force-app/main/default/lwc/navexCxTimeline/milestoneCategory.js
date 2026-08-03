/**
 * The one place milestone categories are defined.
 *
 * A category decides the glyph and the colour of a timeline node, so the row can be read at a
 * glance without opening anything. Categories are matched in order: the first entry whose
 * subjectPatterns hit the activity's subject wins, and anything left over falls back to the
 * activity Type, then to a neutral default.
 *
 * To add a category: append an entry here with a unique `key`, add the matching
 * `.cx-marker_<key>` rule in navexCxTimeline.css, and nothing else needs to change. Put more
 * specific categories above more general ones — "health check" has to be tested before
 * "review", or every health check would be filed as a review.
 */

export const DEFAULT_CATEGORY = {
  key: "activity",
  label: "Activity",
  iconName: "utility:record_alt"
};

export const MILESTONE_CATEGORIES = [
  {
    key: "escalation",
    label: "Escalation",
    iconName: "utility:priority",
    subjectPatterns: [
      /escalat/i,
      /outage/i,
      /severity/i,
      /\bsev[- ]?\d/i,
      /critical issue/i,
      /breach/i
    ]
  },
  {
    key: "risk",
    label: "Risk",
    iconName: "utility:warning",
    subjectPatterns: [
      /\balert\b/i,
      /\brisk\b/i,
      /at[- ]risk/i,
      /churn/i,
      /detractor/i,
      /decline/i,
      /concern/i
    ]
  },
  {
    key: "healthcheck",
    label: "Health check",
    iconName: "utility:heart",
    subjectPatterns: [/health\s*(check|review|score)/i, /\bpulse\b/i]
  },
  {
    key: "kickoff",
    label: "Kickoff",
    iconName: "utility:flag",
    subjectPatterns: [
      /kick[\s-]?off/i,
      /go[\s-]?live/i,
      /\blaunch\b/i,
      /project start/i
    ]
  },
  {
    key: "onboarding",
    label: "Onboarding",
    iconName: "utility:success",
    subjectPatterns: [
      /onboard/i,
      /enablement/i,
      /implementation complete/i,
      /adoption sprint/i
    ]
  },
  {
    key: "ebr",
    label: "Business review",
    iconName: "utility:groups",
    subjectPatterns: [
      /\bebr\b/i,
      /\bqbr\b/i,
      /business review/i,
      /executive review/i
    ]
  },
  {
    key: "relationship",
    label: "Relationship",
    iconName: "utility:user",
    subjectPatterns: [
      /champion/i,
      /sponsor/i,
      /role change/i,
      /departure/i,
      /stakeholder/i
    ]
  },
  {
    key: "renewal",
    label: "Renewal",
    iconName: "utility:refresh",
    subjectPatterns: [/renew/i, /\bcontract\b/i, /expansion/i, /upsell/i]
  },
  {
    key: "review",
    label: "Review",
    iconName: "utility:chart",
    subjectPatterns: [/review/i, /assessment/i, /\baudit\b/i, /check[\s-]?in/i]
  },
  {
    key: "meeting",
    label: "Meeting",
    iconName: "utility:groups",
    activityTypes: ["Meeting"]
  },
  {
    key: "call",
    label: "Call",
    iconName: "utility:call",
    activityTypes: ["Call"]
  },
  {
    key: "email",
    label: "Email",
    iconName: "utility:email",
    activityTypes: ["Email"]
  },
  {
    key: "prep",
    label: "Prep",
    iconName: "utility:task",
    activityTypes: ["Prep"]
  }
];

/**
 * Resolves the category for one milestone. Never returns undefined, so the template can rely on
 * a glyph and a label always being present.
 */
export function resolveCategory({ subject, activityType } = {}) {
  const text = typeof subject === "string" ? subject : "";
  if (text) {
    const bySubject = MILESTONE_CATEGORIES.find((category) =>
      (category.subjectPatterns || []).some((pattern) => pattern.test(text))
    );
    if (bySubject) {
      return bySubject;
    }
  }
  if (activityType) {
    const byType = MILESTONE_CATEGORIES.find((category) =>
      (category.activityTypes || []).includes(activityType)
    );
    if (byType) {
      return byType;
    }
  }
  return DEFAULT_CATEGORY;
}
