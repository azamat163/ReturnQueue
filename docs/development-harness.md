# ReturnQueue development harness

The harness connects Spec Kit, project skills, Swift conventions, MVVM boundaries
and GitLab checks. It is committed project configuration, not a separate server.
For now “snap kit” is interpreted as the existing Spec Kit; no SnapKit dependency
has been introduced. UIKit/SnapKit would be a separate UI decision.

## Skills and authoritative guidance

Launch Codex at the repository root, `app` in the original ChatGPT workspace.
The project skills are:

- [$returnqueue-workflow](../.agents/skills/returnqueue-workflow/SKILL.md): requirements,
  bounded delegation, implementation and evidence.
- [$returnqueue-swift-ios](../.agents/skills/returnqueue-swift-ios/SKILL.md):
  [Swift style](swift-style-guide.md) and [MVVM architecture](ios-architecture.md).
- [$returnqueue-gitlab-release](../.agents/skills/returnqueue-gitlab-release/SKILL.md):
  [GitLab CI](gitlab-ci.md) and [release setup](release-setup.md).

These are project-authored skills based on official Swift/Apple sources. They are
not presented as Apple-published skills. Existing `$speckit-*` skills remain intact.
[Official Codex skill documentation](https://learn.chatgpt.com/docs/build-skills)
describes repository discovery from `.agents/skills` while working inside the repo.
The original chat starts one directory above it, so automatic discovery here has
not been confirmed; skills can be read explicitly or used after opening `app`.

## Development loop

1. **Root manager/orchestrator** selects the current story and task, acceptance
   criteria and required checks from the spec, plan, data model and contracts.
   Use the installed Spec Kit specify/clarify/plan/tasks/analyze skills as needed.
2. **Development lead** delegates implementation tasks to subagents with explicit,
   independent file ownership. The lead integrates shared models and maintains one
   specification and task ledger. Implement a vertical slice within MVVM boundaries;
   P2 photos, Summary and reminders do not become P1 launch dependencies.
3. **Independent code reviewer** reviews the final diff against requirements,
   architecture and correctness. The lead resolves actionable findings before
   handing the resulting diff back for review.
4. **Separate tester/verifier** checks acceptance and runs the required checks for
   that diff. Record the command, environment, result and evidence limits. For
   documentation-only changes, check consistency and links without requiring iOS
   tests. An author cannot serve as the sole reviewer or verifier.
5. **Root** inspects the final diff and handoff evidence, then commits and pushes
   only after findings are resolved and required checks pass. Developers, workers,
   reviewers and testers do not commit or push. A failed or unavailable required
   check blocks publication and is reported; it is never counted as passing.

Material edits after review invalidate the affected review/checks and must return
through those gates. Keep product tasks open until their acceptance is demonstrated,
including required SDK/device checks; a draft or prepared pipeline is not completion.

```sh
./specify integration status --json
python3 tooling/harness.py doctor
python3 tooling/harness.py check
python3 tooling/harness.py verify
```

`doctor` reports local tools and app-project presence; its success is diagnostic.
`check` validates unique requirement/story/task IDs, task references, maintained
guide links, project skill manifests, formatter JSON and CI shell syntax. It does
not establish semantic requirement coverage or validate GitLab's full YAML schema.
`verify` adds offline release-tool tests and the CI quality scripts: strict official
formatter and SwiftPM tests.
It returns failure when a required tool, guide or check fails. No command above
signs, uploads a build or modifies global Codex settings.

The formatter uses [.swift-format](../.swift-format). Run the matching Swift
toolchain's `swift format format --in-place --recursive` on the intended files to
apply layout. Keep broad formatting changes separate from domain behavior.

## Current evidence and remaining integration

The first P1 Core slice now follows the exact JSON contract, optional fields,
CalendarDay and reimbursement events. Its status is recorded in
[slice verification](../specs/001-free-return-prototype/verification.md); independent
review and native 49-test verification passed for this slice. T005 supplies
ReturnQueueStorage and ReturnStore against the fixed
[storage contract](../specs/001-free-return-prototype/contracts/storage.md);
independent review, native 77/77 tests and unsigned Simulator/Release builds
passed on 2026-10-04. Restore and product workflows
remain later tasks. T001 adds an app target/shared scheme and
minimal empty Queue; independent review/build/install/launch gates passed
on 2026-10-04.

Earlier host preparation on 2026-10-03: Spec Kit integration reports no missing or modified
managed files; official Swift 6.2.1 formatter is available. Draft Swift files were
formatted without changing their domain behavior. With writable scoped caches,
the Core module compiled, but XCTest is unavailable in the selected Command Line
Tools environment, so the package test run failed. No passing Core test result or
iOS build was claimed from that earlier environment. A nested sandbox may also prevent SwiftPM's own manifest
sandbox; a local opt-in workaround is described in the CI guide, without changing
normal CI defaults.

Later on 2026-10-03, the user installed full Xcode 26.3 (17C529), with Apple Swift
6.2.4, iOS SDK 26.2 and available simulators. Independent native SwiftPM/XCTest
verification passed all 49 Core/JSON tests (exit 0); T002/T003/T004 are accepted.
Linux Swift 6.2.1 Docker attempts timed out in different places, even with output
redirected; the infrastructure cause remains unresolved. They are failed attempts,
not Linux acceptance. Core's required gate now uses the actual native toolchain;
the minimal T001 target passed independent unsigned builds and review/install/launch
on 2026-10-04. No signed release or product workflow has been validated.

GitLab configuration can be reviewed locally before choosing a GitLab project.
The GitHub repository remains the known remote until the user chooses migration or
CI integration. Runner registration, repository sync, protected refs/variables,
Apple team/bundle ID and signing are external setup. Use GitLab CI Lint in that
project before the first live pipeline, then record actual job/build results.
Keep a successful upload, TestFlight processing and App Store release as separate
outcomes.
