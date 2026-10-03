---
name: returnqueue-workflow
description: Plan, implement, or review a ReturnQueue feature with the installed Spec Kit, bounded subagent ownership, and evidence from local checks. Use for development orchestration in this repository.
---

# ReturnQueue development workflow

Work from the repository root. Read AGENTS.md and the current feature's spec, plan,
tasks, data-model, and relevant contracts before changing behavior. The active
feature is `specs/001-free-return-prototype`. P1 works independently of P2.

Use the installed Spec Kit skills for requirements, planning, tasks and analysis;
leave their managed files intact. `./specify integration status --json` checks the
installation. Read [the harness guide](../../../docs/development-harness.md) for
the local loop. `python3 tooling/harness.py check` checks the foundation;
`python3 tooling/harness.py verify` additionally runs formatter and Core tests.
These checks do not prove iOS behavior or agreement with the product specification.

Follow the user-selected sequence: root manager/orchestrator -> development lead
and implementation subagents -> independent code reviewer -> separate tester/verifier
-> root commit and push. The development lead delegates implementation with explicit
file ownership and owns integration/shared schemas. Keep one specification and task
ledger; trace changes to a story/requirement and task, and update contracts before
changing persisted formats.

Review the final diff and resolve actionable findings before verification. The
author must not be the sole reviewer or verifier. Scope required checks to the
change: documentation alone needs consistency/link checks, not iOS tests. Record
results and limitations. Failed or unavailable required checks block commit/push;
material edits return to the affected review/checks. Only root commits and pushes
after these gates pass. Keep tasks open until acceptance is demonstrated, including
required device checks.

For Swift work read [style](../../../docs/swift-style-guide.md) and
[MVVM boundaries](../../../docs/ios-architecture.md). For GitLab and release work
read [CI](../../../docs/gitlab-ci.md) and [release setup](../../../docs/release-setup.md).
Report actual checks, failures, and remaining setup separately. Preparing a
pipeline does not mean it has run in GitLab or published an application.
