# Verification: first P1 Core/JSON slice

Date: 2026-10-03. Status: T002/T003/T004 accepted by root after separate code review
and independent native verification. Other 25 tasks, including T001/T005/T012,
remain open. This is Core/JSON acceptance, not a working iOS app or release.

## Scope

T002 exact P1 JSON v1/schema; T003 CalendarDay, optional amount/date/location,
USD money, event ledger and manual closure validation; T004 meaningful record tests.
Archive contract tests cover only the decode/encode portion of T012.

Public API and wire contract: [backup.md](contracts/backup.md) and
[backup.schema.json](contracts/backup.schema.json). Old unreleased draft v1
archives are rejected by an exact format marker and field schema.

The filesystem draft is moved from Core into a separate ReturnQueueStorageDraft
target for compilation. Its old load/save semantics are not T005 acceptance;
corrupt-load blocking, confirmed replacement and store serialization remain pending.
No UI, permissions, P2 feature, app target or signing is implemented in this slice.

## Independent review

Reviewer `harness_review` did not author this slice. One finding: the original
nesting test used a top-level array, which was rejected before reaching the depth
guard. The test owner corrected it to exercise ArchiveJSONScanner directly with
an object wrapper: depth 64 accepted, depth 65 rejected. Narrow rereview passed;
no other actionable findings remain. Swift functional files were then frozen.

## Independent native verification — PASS

Verifier `workflow_verifier` did not author the slice. Environment: full Xcode
26.3, build 17C529, Apple Swift 6.2.4; native arm64 macOS SwiftPM/XCTest. Root also
confirmed iOS SDK 26.2 and simulator availability. Xcode installation does not
complete app creation/build task T001.

Executed from the implementation checkout:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test \
  --scratch-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/build \
  --cache-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/cache \
  --config-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/config \
  --security-path /private/tmp/returnqueue-native-verifier-z0w5z9_b/security
```

Exit 0; build 17.19 seconds; **49 XCTest methods, 0 failures, 5.920 seconds**:
Archive 23, Money 6, Record 20. Temporary output log:
`/private/tmp/returnqueue-native-verifier-z0w5z9_b/swift-test.log`.
Native package success is the required scoped Core gate; Docker was an earlier
fallback for the then missing Xcode environment, not an additional release gate.

Independent strict formatter, `python3 tooling/harness.py check` and
`git diff --check` passed. The harness counts 55 requirements, 7 stories, 28 tasks;
it establishes document/skill structure, not feature acceptance.

## Author checks and failed attempts

The model author compiled Core/StorageDraft with Swift 6 and ran local adversarial
smoke checks; scoped formatter passed. The development lead's final full-source
formatter, harness check and diff check passed after the two test-only corrections.

Early Docker mounts lacked execute permission for temporary manifests and failed
before compilation; `/tmp:exec` and `/build:exec` fixed that environment error.
Subsequent Linux Swift 6.2.1 runs built the package, but full runtime attempts
stalled in different locations and timed out, both with and without
`--disable-swift-testing`, and with redirected stdout/stderr. No runtime cause
has been established; neither a wrapper fix nor Linux support is claimed.
A direct full XCTest run of an earlier binary completed 49 methods in 7.92 seconds:
48 passed, one failed because the old Int.min expectation used `.8` instead of
`.08`. The test owner corrected that assertion before independent final native
verification. That earlier binary/result is not final acceptance evidence.

## Remaining checks

- T001 iOS app target creation/build: pending; Xcode/SDK are now available.
- T005/T012/T013 durable storage, corruption blocking, confirmed replacement: pending.
- T016/T028 simulator/device workflows: pending; no iPhone UI exists yet.
- GitLab pipeline, release signing and TestFlight: not run.
- Linux fallback timeout investigation: unresolved; not counted as PASS.

Only root commits/pushes after final-diff review and scoped checks. No author,
reviewer or verifier in this slice published changes.
