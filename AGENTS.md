# Return Queue working project

When working inside the ChatGPT project mirror, its parent AGENTS.md remains
applicable. Synced reference files under the parent's sources/ are read-only:
do not edit, rename, move, or delete them. A standalone clone has no dependency
on those parent files.

The user requests orchestration with subagents and Spec Kit requirements.
Use bounded agent assignments with explicit file ownership; the lead integrates
changes and keeps a single specification. Do not let multiple agents edit a shared
model/schema file concurrently.

Current user preference: free iPhone prototype, no monetization, ads, accounts,
bank integrations or payment processing. Business viability remains unvalidated.
Current specification: specs/001-free-return-prototype/spec.md.
P1 must be independently usable; photos and reminders are P2.

Current stage: requirements, design and development harness. Core Swift files and tests were started
before final requirements, are unverified drafts and need reconciliation before
further implementation. Do not mark backlog tasks complete merely because those
files exist. Verify the iOS app on a real SDK/device before reporting it works.
Never equate specification quality checks with implementation checks.

For Swift/iOS work read docs/swift-style-guide.md and docs/ios-architecture.md.
Use SwiftUI with MVVM, iOS 17+, and target Swift 6 language mode. Keep pure Core
separate from platform/storage Services; UI-facing observable models use MainActor.
Official Swift API Design Guidelines guide APIs; .swift-format defines project layout.

Repo skills returnqueue-workflow, returnqueue-swift-ios and returnqueue-gitlab-release
live alongside the installed Spec Kit skills in .agents/skills. Their maintained
workflow is docs/development-harness.md. Do not rewrite Spec Kit managed skills.
Run python3 tooling/harness.py check for foundation checks and verify for Core quality.
GitLab CI/release configuration is local preparation until the destination, runners,
Xcode app target and Apple signing are configured. Report actual execution separately.
