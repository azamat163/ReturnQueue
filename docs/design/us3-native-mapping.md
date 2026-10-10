# US3: Figma/native mapping

Status: T009–T011 accepted on 2026-10-10 after distinct final source/test review,
independent unsigned Debug/Release builds and all eight UI scenarios on a fresh
simulator, including current disk inspection. The 143 native tests and eight offline
harness checks are reused with exact unchanged-source provenance. Earlier failures
and their bounded fixes remain in verification.md. Root inspected seven actual
large-text screenshots and four fresh recovery/totals/History screenshots without
blocking layout findings; final-layout-reuse-proof.json ties the unchanged layout
to the final source. Full accessibility and physical-device checks remain separate.

[Refund contract](../../specs/001-free-return-prototype/contracts/refunds.md)
defines functional behavior. Root obtained high-fidelity contexts and screenshots
for Waiting, Refund details, History, Record reimbursement and Return details from
[the existing Figma file](https://www.figma.com/design/SMVZHX6PVpx83cRfqM6S2o/Untitled).
Fresh screenshots were obtained directly from nodes Waiting `11:300`, Refund
details `11:362`, History `11:430`, Record reimbursement `11:531` and Return details
`11:243` on 2026-10-10. Host evidence is retained outside this worktree under
`../evidence/us3-2026-10-10/design/`; `provenance.json` records node IDs and image
hashes without temporary download URLs. Earlier context captures used
`/private/tmp/returnqueue-us3-*` paths; these are historical references. Example
purchases are design references, never seeded production data.

| Design intent | Native adaptation |
| --- | --- |
| Queue, Waiting, History navigation | Three working TabView destinations; Summary/Settings/reminders deferred |
| Cards and item details | Native List/NavigationStack, current committed item by ID, native disclosure/back chrome |
| Money/Store credit type choice | Native segmented Picker displays text labels; distinct exact 20pt choice assets remain bundled |
| Recorded amount, day and note | Native Form, exact USD validation, user-controlled Gregorian day, retained draft/errors |
| Closure outcome | Explicit native choice and confirmation; separate money/credit/known difference |
| History status | Closed/Keeping item with recorded outcome/explanation; Last updated uses actual timestamp |
| Palette/type | Existing named tokens, semantic fonts/Dynamic Type; optional ColorSuccess #23755a from History |

Device/status/Home chrome comes from iOS. Tab images render as native templates
with platform selection tint. Remaining icon artwork preserves the exact downloaded
asset appropriate to its 22pt or 20pt design slot; do not scale a 22pt replacement
into the distinct 20pt choice slot. Existing 24pt DetailPin is unchanged.

Original asset provenance: `/private/tmp/returnqueue-us3-assets/provenance.json`.
Fresh byte comparison: `design/bundled-asset-proof.json` in the durable host evidence.
Matching image assets preserve SVG bytes and vector rendering:

| Asset | Original dimensions | SHA-256 |
| --- | --- | --- |
| QueueTabIcon | 22×22 | `b76ce81055589f1ede174ec7efcc7b71cd3464b68c9ade3e48eb250f115f2311` |
| WaitingTabIcon | 22×22 | `fd586d1a9805e04eeb4ea747f07a25bacf3af20fc4c89b918ab3d08f1f747212` |
| HistoryTabIcon | 22×22 | `c5b2f9e5525957e0ba31ab9da723279c21b40cb59ced4bdd5446b1214edc5813` |
| ReimbursementMoney | 22×22 | `82734817d4a4a97e76f619711ffdbb3a9da3e9a7df72f9d57c461f5aba7d5ce0` |
| ReimbursementMoneyChoice | 20×20 | `cae660ba20de9c351fba231bf933d1e3bccaf424fd7159bbe2f09c14b37e814e` |
| ReimbursementCreditChoice | 20×20 | `45428a32a791160fb6f3975fe587b4667d5ba4a51933a4c3790e295ff744dfe7` |

No illustrative bank verification, automatic progress/fullness, late-money claim
or hidden P2 control becomes product behavior. State changes and event deletion
require confirmation; excess is warned without clipping amounts. Unknown expectation
stays unknown. Read failure, raw share warning and owned-copy cleanup retain the
accepted guards. Accessibility IDs belong to actual fields/buttons/labels, avoiding
container identifiers that replace descendants. Final visual and actual disk
evidence is recorded in [feature verification](../../specs/001-free-return-prototype/verification.md);
final lifecycle runtime acceptance passed. Full T015
accessibility, physical-device protection and release acceptance remain separate.
