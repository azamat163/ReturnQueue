# Idea Research: Return Queue

- **Slug**: return-queue
- **Created**: 2026-10-03
- **Evidence confidence (overall)**: low for this business; medium for category context.
- **Method**: synthesis of public sources already inspected during this session before
  invoking the assessment skills. No new URL fetches performed by this stage.

## Users & Demand

- NRF's 2025 release estimates online returns at 19.3% of sales; it reports an average
  of 7.7 online returns in twelve months for surveyed people aged 18–30. This supports
  researching the activity, not willingness to pay for an app. [NRF](https://nrf.com/media-center/press-releases/consumers-expected-to-return-nearly-850-billion-in-merchandise-in-2025)
  — cited, medium; industry association report, not our customer data.
- A subgroup juggling returns across stores may face greater coordination effort.
  ASSUMPTION, low. No interviews or observed sessions have been conducted.

## Prior Art

- Fyld advertises receipt scanning, warranty tracking, return reminders and attachments.
  US App Store lists $3.99/month and $34.99/year. [Fyld](https://apps.apple.com/us/app/fyld/id6760244721)
  — cited, high for advertised functionality and listed price; app not tested.
- Ajar advertises local receipt processing, user confirmation, refund tracking,
  dated merchant-policy sources, and a free starter library including export and
  reminders. Therefore privacy, OCR, and refund tracking alone are weak positioning.
  [Ajar](https://ajar.susnoodle.com/) — cited, high for vendor statements; not verified
  by hands-on testing.
- No prior internal application or assessment was found. Source: local workspace inspection.

## Market & Context

- NRF's estimate of $849.9 billion in 2025 returned merchandise is a retailer operations
  metric. It MUST NOT be used as our addressable software market or revenue forecast.
  [NRF](https://nrf.com/media-center/press-releases/consumers-expected-to-return-nearly-850-billion-in-merchandise-in-2025)
  — cited, medium.
- Retailer order pages, emails, calendar reminders, screenshots, and Notes are possible
  alternatives. ASSUMPTION, medium; actual usage needs customer observation.

## Data & Constraints

- Ajar already addresses return-window provenance and delivery dates. ASSUMPTION:
  maintaining a reliable automated catalog adds work that a small first release may
  not justify. Use customer-confirmed dates in an experiment. [Ajar](https://ajar.susnoodle.com/)
- The workspace has no app code. The active Apple developer tools are Command Line
  Tools; an iOS build environment was not verified. Source: local environment inspection.
- Founder time budget, acquisition budget, and distribution access remain unknown.

## Evidence Against the Idea

- Direct competitors already cover much of the proposed workflow, including refund
  tracking. [Ajar](https://ajar.susnoodle.com/), [Fyld](https://apps.apple.com/us/app/fyld/id6760244721)
- The inspected Fyld listing has insufficient ratings for an overview. A published
  paywall gives no evidence about actual conversions. [Fyld](https://apps.apple.com/us/app/fyld/id6760244721)
- Extra data entry may outweigh the benefit; a user may prefer free store tools.
  ASSUMPTION, low. Adding automation could increase complexity without fixing adoption.

## Gaps & Open Questions

- How often does the target subgroup have multiple simultaneous returns?
- Which step caused a recent measurable loss or inconvenience?
- Do competitors already support grouping by drop-off location sufficiently well?
- Can a user add a real return in under 45 seconds and keep it current?
- Is there real purchase intent at a stated price?

## Sources

Previously inspected source material; policy: reused-existing-session-evidence,
not a new fetch under this skill. URL host classification recorded for provenance:

- https://nrf.com/media-center/press-releases/consumers-expected-to-return-nearly-850-billion-in-merchandise-in-2025 — host: nrf.com; unrecognized by intake allowlist.
- https://apps.apple.com/us/app/fyld/id6760244721 — host: apps.apple.com; unrecognized by intake allowlist.
- https://ajar.susnoodle.com/ — host: ajar.susnoodle.com; unrecognized by intake allowlist.
