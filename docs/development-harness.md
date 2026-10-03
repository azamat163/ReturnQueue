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

1. Read the current story, requirement, task, data model and relevant contracts.
   Use the installed Spec Kit specify/clarify/plan/tasks/analyze skills as needed.
2. Assign independent file ownership for parallel work. The lead integrates shared
   models and retains a single specification.
3. Implement a vertical slice within the MVVM boundaries. Preserve P1 usability;
   P2 photos, Summary and reminders do not become P1 launch dependencies.
4. Run checks suitable for the changed behavior. Record the command, environment,
   outcome and limits of the evidence before marking a product task complete.

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

The current code is a draft built before the final product requirements. Formatting
does not reconcile its model. Core tests can only prove assertions about that draft;
the current spec requires optional fields, CalendarDay and reimbursement events.
The app target and device workflow still need implementation.

Local preparation on 2026-10-03: Spec Kit integration reports no missing or modified
managed files; official Swift 6.2.1 formatter is available. Draft Swift files were
formatted without changing their domain behavior. With writable scoped caches,
the Core module compiled, but XCTest is unavailable in the selected Command Line
Tools environment, so the package test run failed. No passing Core test result or
iOS build is claimed. A nested sandbox may also prevent SwiftPM's own manifest
sandbox; a local opt-in workaround is described in the CI guide, without changing
normal CI defaults.

GitLab configuration can be reviewed locally before choosing a GitLab project.
The GitHub repository remains the known remote until the user chooses migration or
CI integration. Runner registration, repository sync, protected refs/variables,
Apple team/bundle ID and signing are external setup. Use GitLab CI Lint in that
project before the first live pipeline, then record actual job/build results.
Keep a successful upload, TestFlight processing and App Store release as separate
outcomes.
