# Return Queue working project

When working inside the ChatGPT project mirror, its parent AGENTS.md remains
applicable. Synced reference files under the parent's sources/ are read-only:
do not edit, rename, move, or delete them. A standalone clone has no dependency
on those parent files.

The user requests this workflow: root manager/orchestrator -> development lead and
implementation subagents -> independent code reviewer -> separate tester/verifier
-> root commit and push. The development lead delegates implementation with explicit
file ownership, integrates changes and keeps one specification and task ledger.
Do not let multiple agents edit a shared model/schema file concurrently.
The author must not be the sole reviewer or verifier. Developers, workers, reviewers
and testers do not commit or push; only root does, after review findings are resolved
and required checks pass on the final diff. A failed or unavailable required check
blocks commit/push and must be reported. Scope checks to the change: documentation
alone does not require iOS tests. Material changes after review return to the relevant
review and checks. See docs/development-harness.md for the handoff requirements.

Current user preference: free iPhone prototype, no monetization, ads, accounts,
bank integrations or payment processing. Business viability remains unvalidated.
Current specification: specs/001-free-return-prototype/spec.md.
P1 must be independently usable; photos and reminders are P2.

Current stage: first P1 Core/model/archive-codec slice accepted after independent
review and native 49/49 XCTest; evidence lives in specs/001-free-return-prototype/verification.md.
Core has no filesystem access. T005 replaced the filesystem draft with
ReturnQueueStorage and a serialized ReturnStore; the contract lives in
specs/001-free-return-prototype/contracts/storage.md. Independent review, native
77-test suite and unsigned Simulator/Release builds passed on 2026-10-04.
T001 now has a minimal SwiftUI empty Queue, Xcode project/shared ReturnQueue scheme
and local Core package dependency. Independent review, unsigned Simulator/Release
builds and simulator install/launch passed on 2026-10-04. T006 adds real Add/edit/details,
minimal list navigation and safe recovery sharing over the accepted storage.
Independent review, native 93/93 tests, unsigned builds and four fresh-simulator UI
scenarios passed on 2026-10-04. T007/T008 now add planned-only location grouping,
deterministic day/creation/UUID ordering and a local-day past badge; contract:
specs/001-free-return-prototype/contracts/queue.md. Independent review, native
106/106 tests, both unsigned builds and five fresh-simulator UI scenarios passed.
T009–T011 add manual reimbursements, explicit closure/correction and Waiting/History.
Independent review, 143 native tests, both unsigned builds and all eight fresh-simulator
UI scenarios passed on 2026-10-10. T001–T011 are accepted; 17 tasks remain open.
The complete P1 workflow, full restore and P2 are pending. Full Xcode 26.3, iOS SDK
and simulators are available. Do not mark tasks complete merely because files exist.
Verify the iOS app on a real SDK/device before reporting it works.
Never equate specification quality checks with implementation checks.

For Swift/iOS work read docs/swift-style-guide.md and docs/ios-architecture.md.
Use SwiftUI with MVVM, iOS 17+, and target Swift 6 language mode. Keep pure Core
separate from platform/storage Services; UI-facing observable models use MainActor.
Official Swift API Design Guidelines guide APIs; .swift-format defines project layout.

Repo skills returnqueue-workflow, returnqueue-swift-ios and returnqueue-gitlab-release
live alongside the installed Spec Kit skills in .agents/skills. Their maintained
workflow is docs/development-harness.md. Do not rewrite Spec Kit managed skills.
Run python3 tooling/harness.py check for foundation checks and verify for Core quality.
GitLab CI/release configuration is local preparation until the destination, runners
and Apple signing are configured. The app target and shared UI-test scheme exist;
remote CI/signing/release execution must be reported separately.
