<!-- Sync Impact Report
Version: 1.0.0 -> 1.1.0 (free prototype scope adopted)
Principles: unchanged. Added constraints: user-authorized free validation, no monetization.
Removed: none. Deferred placeholders: none.
-->
# US iPhone Pet Project Constitution

## Core Principles

### I. Evidence Before Scope
Every candidate MUST name one audience, a recurring situation, the current workaround,
and a measurable benefit. Research MUST separate observed facts, vendor claims,
inferences, and untested hypotheses. Competitors and industry market size MUST NOT be
presented as proof that our product will acquire users or receive payment.

### II. One Useful End-to-End Workflow
The first release MUST solve one complete task for one audience. Each proposed feature
MUST support that task or resolve a demonstrated obstacle. Prefer native platform
capabilities and local storage when they meet the need. Add servers, integrations, and
AI only when evidence supports the added operating cost and complexity.

### III. User Control and Data Durability
Collect only data required for the workflow. Ask for permissions at the point of use.
Users MUST be able to export and delete their records. Important records MUST have a
recoverable backup path before a production release. Externally shared information MUST
be previewable. Sensitive content MUST NOT appear in analytics or diagnostic logs.

### IV. Monetization Matches Use
Document pricing as an experiment until real users pay. Recurring charges MUST provide
recurring value; consider a one-time purchase for infrequent, fully local utilities.
Specify the free allowance, paid benefit, restore behavior, and ongoing costs before
implementing a paywall. Revenue estimates MUST state conversion, retention, acquisition
cost, platform fees, and tax assumptions rather than imply guaranteed income.

### V. Verification Is Part of Delivery
Each feature spec MUST include observable acceptance criteria and important failure
cases. Run checks appropriate to the change. Persistence, import/export, paid access,
and any deadline calculations require meaningful verification. Record unavailable
checks explicitly; never describe unbuilt or untested iOS code as a working release.

## Product Constraints

The target platform is iPhone/iOS and the first audience is in the United States.
The user has authorized a free Return Queue prototype for usefulness testing.
Monetization, subscriptions, paywalls, advertising and paid limits are deferred.
Market demand and willingness to pay remain unvalidated; do not require payment evidence
to proceed with this explicitly authorized free experiment.
Minimum iOS version is chosen in the implementation plan.
Use English for the first customer-facing experience. Support US conventions where
relevant without hardcoding currency, locale, or time zone into the data model.
Treat third-party policies as dated source material; show uncertainty and allow users
to correct inferred values. Avoid legal, financial, or medical promises.
Synced project reference files under the parent sources/ directory are read-only.

## Development Workflow

The lead agent coordinates research, specification, implementation, and review.
Delegate bounded tasks when useful within the user's request; retain responsibility
for decisions and integration. Record scope and evidence in this repository so future
sessions can continue from the same basis.

Follow the Spec Kit sequence: assess the idea, document the selected problem, write the
specification, choose implementation details, create tasks, implement, and verify.
Review uncertain assumptions before expanding scope. A candidate may move to a limited
validation experiment without being declared a validated business.
Do not contact prospects, publish, or incur charges without user authorization.

## Governance

This constitution guides project decisions subject to the user's instructions and
parent workspace rules. Amend it with a recorded rationale and the date of change.
Use a major version for incompatible principle changes, a minor version for new
principles or material expansion, and a patch for clarifications. Specifications and
plans MUST state material exceptions and their rationale. Review compliance before
claiming a milestone complete.

**Version**: 1.1.0 | **Ratified**: 2026-10-03 | **Last Amended**: 2026-10-03
