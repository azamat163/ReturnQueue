# Verification: first P1 Core/JSON slice

Date: 2026-10-03. First-slice acceptance: T002/T003/T004 accepted by root after
separate code review and independent native verification. At that point the other
25 tasks, including T001/T005/T012, remained open. This historical result is
Core/JSON acceptance, not a working P1 iOS app or release.

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

## Checks remaining at Core handoff (2026-10-03)

- T001 iOS app target creation/build: pending; Xcode/SDK are now available.
- T005/T012/T013 durable storage, corruption blocking, confirmed replacement: pending.
- T016/T028 simulator/device workflows: pending; no iPhone UI exists yet.
- GitLab pipeline, release signing and TestFlight: not run.
- Linux fallback timeout investigation: unresolved; not counted as PASS.

Only root commits/pushes after final-diff review and scoped checks. No author,
reviewer or verifier in this slice published changes.

## T001 — minimal iOS bootstrap (separate slice)

Date: **2026-10-04, Europe/Moscow**. Status: **T001 accepted by root** after
independent review, both unsigned builds and simulator install/launch smoke passed.
At the T001 handoff: T001/T002/T003/T004 complete; 24 tasks remained open.
The previous Core acceptance above remains valid; Core sources and its tests
are unchanged in this slice.

Scope: checked-in ReturnQueue.xcodeproj, shared ReturnQueue scheme, iOS 17+,
Swift 6 language mode, SwiftUI @main entry and truthful English empty Queue.
The app links the existing local Swift package's ReturnQueueCore product; domain
sources are not copied into the app target. Provisional local Bundle ID:
com.azamat163.returnqueue. Apple registration, team and signing credentials
have not been configured for this project.

No persistence, return editor, operational actions or P2 functionality is provided.
At that handoff T005/T006 and full P1 acceptance remained open. Release Archive
configuration was prepared, but the scheme had no app test target yet; the existing
release script blocked distribution until simulator app tests/test plan and signing
configuration were supplied. The GitLab YAML/release scripts were unchanged.

Author unsigned builds: **PASS**, exit 0 / BUILD SUCCEEDED for both:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/returnqueue-t001-sim-author \
  -clonedSourcePackagesDirPath /private/tmp/returnqueue-t001-packages-author \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/returnqueue-t001-device-author \
  -clonedSourcePackagesDirPath /private/tmp/returnqueue-t001-packages-author \
  CODE_SIGNING_ALLOWED=NO build
```

Logs `/private/tmp/returnqueue-t001-sim-author.log` and
`/private/tmp/returnqueue-t001-device-author.log`. These are unsigned builds,
not a signed archive/IPA or distribution. Earlier sandboxed build failed on
SwiftPM cache/CoreSimulator access; scoped escalation permitted the actual SDK
builds above. The only reported build warning was skipped AppIntents metadata
(no AppIntents dependency). Native strict formatter, plutil project validation,
harness check and diff check passed.

Independent reviewer `harness_review`: **PASS**, no actionable findings. Functional
Swift/project files remained unchanged after this review.

Independent verifier `workflow_verifier`: both unsigned builds **PASS**, exit 0:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t001-debug-verifier-4cbjvmjn/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t001-release-verifier-_6linzof/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Logs `/private/tmp/rq-t001-debug-verifier-4cbjvmjn/build.log` and
`/private/tmp/rq-t001-release-verifier-_6linzof/build.log`.

Simulator smoke **PASS**: iPhone 17 / iOS 26.3, UDID
`5449F349-65C1-4DDF-B11E-9FCF209FBD50`. It was initially Shutdown and had no installed
ReturnQueue bundle. Verifier booted it, installed the Debug app and launched:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun simctl install \
  5449F349-65C1-4DDF-B11E-9FCF209FBD50 \
  /private/tmp/rq-t001-debug-verifier-4cbjvmjn/DerivedData/Build/Products/Debug-iphonesimulator/ReturnQueue.app
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun simctl launch \
  5449F349-65C1-4DDF-B11E-9FCF209FBD50 com.azamat163.returnqueue
```

Launch returned PID **50773**, still alive after three seconds. Screenshot visually
passed: English empty Queue, no fake purchases or unavailable controls. Root also
inspected the screenshot and accepted this gate. Verifier terminated its test app and returned only the used, initially Shutdown
simulator to Shutdown after the smoke run.

Temporary launch metadata `/private/tmp/rq-t001-debug-verifier-4cbjvmjn/launch.json`;
screenshot `/private/tmp/rq-t001-debug-verifier-4cbjvmjn/returnqueue-launch.png`.
Root retained a stable task artifact outside the repository:
`/Users/aagataev/.codex/visualizations/2026/10/03/01a1012c-4737-7c71-8587-6600853c8fec/returnqueue-bootstrap.png`.

This acceptance proves bootstrap compile/install/launch only. It does not complete
T005 persistence, T006 editor, T008 grouping/navigation, T015 accessibility or T016
full P1 workflows. No signed archive, IPA, TestFlight or GitLab pipeline was run.

## T005 storage slice — 2026-10-04

Status: **T005 accepted by root** after separate review and final independent
verification. At that storage handoff five tasks were accepted (T001–T005);
the other 23 remained open.
Frozen Core/wire files and app UI
behavior are unchanged. The local app target links the new ReturnQueueStorage
product so builds compile its iOS protection branch.

Author unsigned builds passed, exit 0, using Xcode 26.3 / Apple Swift 6.2.4:

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t005-author-debug-sp88px1q/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t005-author-release-wc_j356l/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Logs: `/private/tmp/rq-t005-author-debug-sp88px1q/build.log` and
`/private/tmp/rq-t005-author-release-wc_j356l/build.log`.
Final author native XCTest passed: **77 tests, 0 failures**, 8.301 seconds, exit 0;
49 Core + 12 repository + 16 store tests. All three permission-specific tests ran
without skips as an unprivileged user. Those tests explicitly skip only UID 0;
directory/malformed/version/size cases always run. The reviewer identified this
portability issue; the owner split/fixed the cases before the final author run.

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test \
  --scratch-path /private/tmp/rq-t005-author-tests-lbrjv4kd/build \
  --cache-path /private/tmp/rq-t005-author-tests-lbrjv4kd/cache \
  --config-path /private/tmp/rq-t005-author-tests-lbrjv4kd/config \
  --security-path /private/tmp/rq-t005-author-tests-lbrjv4kd/security
```

Log: `/private/tmp/rq-t005-author-tests-lbrjv4kd/swift-test.log`.
Strict repository Swift formatter lint and diff check passed. Independent reviewer
accepted the final Services/tests diff after the focused portability correction;
root reviewed Package/project/docs integration without findings.

Final independent native XCTest **PASS**: 77/77, 0 failures, 0 skips, UID 501,
Apple Swift 6.2.4; build 18.59 seconds, test suite 8.298 seconds, exit 0.

```sh
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcrun swift test \
  --scratch-path /private/tmp/rq-t005-final-tests-81e72lxo/build \
  --cache-path /private/tmp/rq-t005-final-tests-81e72lxo/cache \
  --config-path /private/tmp/rq-t005-final-tests-81e72lxo/config \
  --security-path /private/tmp/rq-t005-final-tests-81e72lxo/security
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t005-final-debug-u5mpa7nk/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer xcodebuild \
  -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t005-final-release-2p0sju1h/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Both independent unsigned builds **PASS**, exit 0. Logs:
`/private/tmp/rq-t005-final-tests-81e72lxo/swift-test.log`,
`/private/tmp/rq-t005-final-debug-u5mpa7nk/build.log`,
`/private/tmp/rq-t005-final-release-2p0sju1h/build.log`.
Independent strict lint, foundation harness, diff check, project plist and shared
scheme checks passed. Services/tests were authored separately and reviewed by
`harness_review`; root independently reviewed integration before acceptance.
The verifier authored the storage tests and ran final verification after the
distinct review; neither implementation owner was the sole reviewer.

These checks prove host persistence semantics and compilation of iOS protection
code. Runtime device file protection, app persistence UI, full replacement/restore,
signing and release readiness remain separate checks. T012/T013/T014/T016 remain
open. No Linux support/PASS or remote GitLab run is claimed. Documentation-only
acceptance changes after these gates require scoped consistency checks, not a new
Core runtime run.

## T006 author checks and review handoff (2026-10-04)

At this author handoff T006 remained open until distinct review and independent
simulator verification; the final accepted results are recorded below.
Presentation/session and editor tests were authored separately from UI/services.
The production composition uses the existing Application Support archive and
real ReturnStore; DEBUG UI fixtures use separate UUID directories inside the
test app container. No Core model, wire format or accepted storage source changed.

Author native XCTest passed: **93/93 tests, 0 failures**, 8.332 seconds, exit 0
(49 Core + 28 Storage + 16 Presentation). Command used the same Xcode 26.3
DEVELOPER_DIR and `xcrun swift test` with scratch/cache/config/security under
`/private/tmp/rq-t006-author-tests-fzu8kxfr`; log `swift-test.log` there.
Author unsigned generic Simulator Debug and generic iOS Release builds passed.
Final logs after the focused recovery fix:
`/private/tmp/rq-t006-author-debug-c547r87p/build-final-cleanup.log` and
`/private/tmp/rq-t006-author-release-us90bhza/build-final-cleanup.log`.

The first two full UI runs failed (1/4 passed each); those results are retained:
`/private/tmp/rq-t006-author-ui-tcz2poa1/Results.xcresult` and
`/private/tmp/rq-t006-author-ui-final-5hpwl2lm/Results.xcresult`.
Actual screen recordings confirmed expanded optional fields hidden behind the
keyboard accessory, and the native recovery share sheet whose system close
action was localized independently of the app. Corrections target the editor
Form and safe gesture bounds, scope the nested alert action, and use the system
share close identifier with a filename assertion. The enclosing DisclosureGroup
identifier also overwrote child field IDs; it now belongs only to its label.
Visibility checks include the navigation/keyboard bounds because XCTest reported
fields under the navigation bar as hittable. Targeted diagnostics are retained in
`/private/tmp/rq-t006-author-ui-targeted-d77yhje7/Results.xcresult` and
`/private/tmp/rq-t006-author-ui-create-fixed-u49v2kfx/Results.xcresult`.

Baseline author UI **4/4 PASS**, 0 failures, 222.776 seconds, exit 0:
`/private/tmp/rq-t006-author-ui-full-four-pls9yg8g/Results.xcresult`, with adjacent
`ui-test.log`. Actual cases cover create/optional values/relaunch/edit/cancel,
invalid inputs/unknown values, failed atomic write and blocked corrupt-load/raw
share/explicit retry. This baseline preceded the reviewer's focused cleanup fix.
The reviewer found that a failed temporary-copy cleanup could be forgotten by a
new export. RootView now reserves export/cleanup operations before starting Tasks,
blocks export while a copy remains, and keeps Retry cleanup available independently
of the alert and load phase. APIs, Core, Storage and unit tests did not change.
Affected author recovery UI **PASS**, 34.671 seconds, exit 0:
`/private/tmp/rq-t006-author-ui-cleanup-fixed-w1ndolr6/Results.xcresult` and adjacent
`ui-test.log`. Both unsigned builds and strict recursive lint passed on this tree.
The independent verifier must run all four UI cases on the final reviewed tree;
no test method is excluded from the required acceptance run.

Root visually accepted rendered Add and saved Detail against the supplied Figma
intent/native mapping, including exact package/pin SVGs, colors and native controls.
Stable screenshots are `/Users/aagataev/.codex/visualizations/2026/10/03/01a1012c-4737-7c71-8587-6600853c8fec/returnqueue-add-return.png`
and the adjacent `returnqueue-return-detail.png`. The source screenshots and
attachments remain in the author xcresults; see `docs/design/t006-native-mapping.md`.
Strict recursive Swift lint and the foundation harness passed; these do not
substitute for final independent verification. At this author handoff distinct
final review/verification were pending. GitLab CI, signing and release remain unrun.

## T006 final independent checks (2026-10-04)

Distinct `harness_review` accepted the final source after the cleanup fix; root
reviewed integration and rendered Add/Detail. The independent verifier matched all
48 source fingerprints before/after checks. Native **93/93 PASS**, 0 failures,
0 skips, UID 501, Apple Swift 6.2.4: elapsed 26.608 seconds, suite 8.238 seconds.
Unsigned Debug Simulator and Release iOS builds **PASS**, exit 0, elapsed 34.514
and 17.185 seconds. All **4/4 UI XCTest PASS**, 0 failures/skips, suite 232.885
seconds, exit 0, on fresh iPhone 17 / iOS 26.3 simulator
`3C98A0D0-7F6F-46E2-89A8-0F0D3C25FF5B` (initially Shutdown).

All commands used `DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer`
from the implementation checkout. Evidence root:
`/private/tmp/rq-t006-final-verifier-1h7khfei/`.

```sh
swift test --scratch-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/build \
  --cache-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/cache \
  --config-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/config \
  --security-path /private/tmp/rq-t006-final-verifier-1h7khfei/native/security
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t006-final-verifier-1h7khfei/debug-derived \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t006-final-verifier-1h7khfei/release-derived \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'platform=iOS Simulator,id=3C98A0D0-7F6F-46E2-89A8-0F0D3C25FF5B' \
  -derivedDataPath /private/tmp/rq-t006-final-verifier-1h7khfei/debug-derived \
  -resultBundlePath /private/tmp/rq-t006-final-verifier-1h7khfei/UIResults.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Logs: `native.log`, `debug-build.log`, `release-build.log`, `ui-test.log` under
that evidence root; command/result JSONs and `UIResults.xcresult` preserve the
actual invocations/outcomes. Strict recursive lint, harness, diff, plist and scheme
checks passed. Disk inspection (`disk-verification.json`) confirmed four isolated
UUID archives: edited title/date/7999 cents survived relaunch; corrected unknowns
remain null; failed write retained Original sneakers; explicit recovery restored
bytes matching `test-original.json` SHA-256. Production-default archive was absent
on this fresh test device and the recovery directory contained no leftover copies.

Root accepted T006 after these scoped gates: T001–T006 completed, 22 tasks open.
Fresh test-device cleanup is recorded by the verifier's final handoff; simulator
data and SDK/build caches are not repository artifacts. Root also reviewed the
independent Add/Detail/native-share screenshots; stable files reside in the same
visualization directory as above (`returnqueue-recovery-share.png` added).
No physical-device protection, full backup/restore, P2, remote GitLab, signing or
release acceptance is inferred from these scoped results.

## T007/T008 Queue: tests-first preparation (2026-10-04)

Base: accepted T006 commit `f08bf00a60bfa8682556165eef5dbe999b84bbd6`.
Root approved the pure selector/Presentation contract in `contracts/queue.md`;
an independent test author materialized seven Core Queue tests and six
QueueViewModel tests before implementation. Fresh native SwiftPM run gave the
expected **RED**, exit 1, elapsed 11.49 seconds: new ReturnQueueSelector/
QueueViewModel symbols were absent. Log:
`/private/tmp/rq-t007-tests-first-red-f6c6e2dq/swift-test.log`.
Strict scoped formatter and diff check passed for those test files.

This is intentional tests-first evidence, not a passing implementation gate.
At this tests-first checkpoint T007/T008 were open: source, author checks, distinct
review, independent native/build/five UI scenarios and rendered acceptance were pending.
Root obtained Queue Figma context/screenshot and the exact 16pt pin before edits;
native mapping is recorded in `docs/design/t008-native-mapping.md`.

### Author checks and first UI diagnosis

Evidence root: `/private/tmp/rq-t008-author-_2dbit5z/`. Environment:
`DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer`, Apple Swift 6.2.4;
root-created iPhone 17 simulator `53F66FB0-A7CC-4BA8-ACC8-6E2DAD58FCFC`.
The xcresult reports runtime iOS 26.3.1, build 23D8133.

Native **106/106 PASS**, 0 failures, suite 5.785 seconds, elapsed 20.970 seconds;
`native.log` and `native-result.json` preserve the command/result with isolated
SwiftPM scratch/cache/config/security paths. Generic unsigned Debug Simulator
build **PASS**, elapsed 10.601 seconds; Release generic iOS build **PASS**,
elapsed 12.912 seconds. Logs/results: `debug-build.log`, `debug-result.json`,
`release-build.log`, `release-result.json`; both use `CODE_SIGNING_ALLOWED=NO`.

First all-five UI run **FAIL**, exit 65, elapsed 342.224 seconds: four cases passed,
including Queue grouping/date ordering/merchant/Cancel/durable regroup/relaunch;
recovery failed tapping background Retry after native share Close.
`UIResults.xcresult`, `ui-test.log` and exported `attachments/` are retained.
The actual failure hierarchy still contained ActivityListView/header.closeButton;
existence of Retry alone did not prove the share had disappeared or Retry was hittable.
Disk proof `failed-recovery-and-trip-disk.json` confirmed the corrupted original,
valid original backup and byte-equal raw copy were retained. The failed attempt
did not demonstrate cleanup; the production-default archive was absent.

The test owner added bounded native-close disappearance and Retry enabled/hittable
checks with diagnostics. No sleep, repeated Close tap or weakened recovery assertion
was introduced; no app/Storage source changed. Focused reviewer approved the helper.
Targeted real recovery **PASS**, exit 0, elapsed 41.823 seconds:
`RecoveryResults.xcresult`, `recovery-test.log`, `recovery-result.json`.
The final all-five author run subsequently **PASS**, exit 0, suite 317.990 seconds,
elapsed 326.517 seconds: `FinalUIResults.xcresult`, `final-ui-test.log` and
`final-ui-result.json`. Final attachments are exported under `final-attachments/`.
`final-disk-proof.json` retains the five actual fixture archives (1/1/1/3/1 records),
with the edited trip's locations/dates, the recovered archive byte-equal to its
valid backup and the failed-write record unchanged. The production-default
archive remains absent. Only the previously documented first failed-attempt
raw copy remained on this reused author device; current successful exports were
cleaned. This is not proof of an empty recovery directory on a fresh device.

Distinct final code review **PASS**, no actionable findings; all 57 final source
fingerprints matched after the author run (`source-after-author.json`). Independent
QA was still pending at this author handoff; acceptance is recorded below.
The original 57 source hashes are in `source-fingerprints.json`; the reviewed helper
changes only `ReturnQueueUITests.swift` in `source-fingerprints-fixed.json`.

Root compared actual Queue normal/larger text against Figma/native mapping and
accepted that visual scope. Stable screenshots: task visualization directory
`returnqueue-queue.png` and `returnqueue-queue-large-text.png`; report
`/private/tmp/returnqueue-t008-root-visual.json`. This scoped check does not close
T015 or claim full VoiceOver/Dynamic Type acceptance.


### Independent final verification and acceptance (2026-10-04)

Distinct final code review passed without actionable findings. A separate verifier
then checked the same 57 source fingerprints on a fresh isolated iPhone 17
simulator `4562D4B1-F158-4B51-9C08-94084146BAE5`, using full Xcode 26.3,
Apple Swift 6.2.4 and UID 501. Evidence root:
`/private/tmp/rq-t008-final-verifier-biwm3z_m/`; the final machine-readable verdict
is `verification-report.json`.

| Required check | Actual result |
| --- | --- |
| Native package XCTest | 106/106, 0 failures, 0 skips; 56 Core + 28 Storage + 22 Presentation; suite 5.751 s, elapsed 19.103 s, exit 0 |
| Generic Simulator Debug build | Unsigned PASS, elapsed 22.916 s, exit 0 |
| Generic iOS Release build | Unsigned PASS, elapsed 12.489 s, exit 0 |
| Fresh-simulator UI XCTest | 5/5, 0 failures, 0 skips; suite 317.367 s, elapsed 333.913 s, exit 0 |
| Explicit local harness verify | 8 offline release-tool checks + 106 native tests, 0 failures/skips; native suite 5.626 s, elapsed 19.693 s, exit 0 |
| Static checks | Recursive strict formatter, foundation harness, project plist, shared UI-test scheme, diff and exact 16pt pin hash PASS |

All commands ran from the implementation checkout with
`DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer`:

```sh
swift test --scratch-path /private/tmp/rq-t008-final-verifier-biwm3z_m/native/build \
  --cache-path /private/tmp/rq-t008-final-verifier-biwm3z_m/native/cache \
  --config-path /private/tmp/rq-t008-final-verifier-biwm3z_m/native/config \
  --security-path /private/tmp/rq-t008-final-verifier-biwm3z_m/native/security
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rq-t008-final-verifier-biwm3z_m/debug-derived \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/rq-t008-final-verifier-biwm3z_m/release-derived \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ReturnQueue.xcodeproj -scheme ReturnQueue -configuration Debug \
  -destination 'platform=iOS Simulator,id=4562D4B1-F158-4B51-9C08-94084146BAE5' \
  -derivedDataPath /private/tmp/rq-t008-final-verifier-biwm3z_m/debug-derived \
  CODE_SIGNING_ALLOWED=NO \
  -resultBundlePath /private/tmp/rq-t008-final-verifier-biwm3z_m/UIResults.xcresult \
  -parallel-testing-enabled NO test
SWIFT_VERSION=6.2.4 RQ_SWIFTPM_DISABLE_SANDBOX=1 python3 tooling/harness.py verify
```

The harness invocation had `CI` unset; its explicit local sandbox opt-in does not
change the CI default. Exact invocations and outcomes are retained in
`native-command.json`, `debug-command.json`, `release-command.json`,
`ui-command.json`, `harness-command.json` and corresponding result JSONs.
Logs: `native.log`, `debug.log`, `release.log`, `ui.log`, `harness-verify.log`;
`UIResults.xcresult` and four exported screenshots preserve actual runtime evidence.

`disk-verification.json` confirmed five isolated UUID archive roots with seven
records: the trip's edited location/date persisted after relaunch; the earlier
edited 7999-cent/date/location record remained correct; failed write retained
Original sneakers. Recovered original bytes matched the backup. On this fresh
device the recovery temporary directory was empty and the production-default
archive did not exist. This final proof is separate from the first author failure
and its retained orphan copy described above.

The 57 reviewed source fingerprints matched before and after all checks.
`cleanup.json` confirms the verifier's own simulator shutdown/delete returned
exit 0 and the device was absent afterward; only its own build caches were removed.
Logs, JSON proofs, xcresult and PNGs remain. Root also removed its separate author
device after evidence capture; `/private/tmp/returnqueue-t008-author-simulator.json`
and the author's `cache-cleanup.json` retain that cleanup evidence.

Root accepted T007/T008: **T001–T008 completed, 8 of 28 tasks; 20 open**. Root
reviewed the final independent grouped Queue screenshot; the stable normal image
`returnqueue-queue.png` now comes from final QA, while
`returnqueue-queue-large-text.png` retains the author-device larger-text check.
Both are in the task visualization directory; provenance is in
`/private/tmp/returnqueue-t008-root-visual.json`.

Full P1/P2, T015/T016, physical-device protection, full backup/restore, remote GitLab,
Apple signing, TestFlight and release acceptance remain open. These results accept
only this Queue slice and the regression checks above.


## US3 T009/T010/T011: tests-first preparation (2026-10-04)

Base: `00ebe88a436cdc5f9570a37b38ff58d5061524b3`. Root approved the exact
[refund contract](contracts/refunds.md) and an independent early contract audit
found no blockers; that audit does not substitute for final source review.
The independent test author materialized 37 new native tests (14 Core, six Storage,
17 Presentation) before production symbols existed. Fresh native SwiftPM returned
expected **RED**, exit 1, elapsed 12.182 seconds, for missing RefundSummary,
ReturnMutation/new form/action APIs and Store mutation/confirmation entry points.
Evidence: `/private/tmp/rq-t009-tests-first-red-3bnic5w5/` (`command.json`,
`result.json`, `swift-test.log`). This is intentional tests-first evidence, not an
implementation PASS. The command used isolated scratch/cache/config/security,
full Xcode 26.3, UID 501 and explicit local `--disable-sandbox`.

`test-materialization.json` records the four new native-test files plus the three
appended UI journeys, formatter/parse/diff checks and byte invariance of the
accepted 106 native cases/five UI cases and their existing helpers. The resulting
required suite is 143 native tests/eight UI cases. A new Storage assertion targets
retention of saved createdAt before validating a caller's nonfinite createdAt,
preserving the accepted update contract; it passed in the initial native author run below.

Source implementation is authorized after that RED; author runtime, final distinct
source review, fresh independent QA and rendered US3 checks are pending. T009–T011
remain unchecked; no new implementation, complete P1/P2 or release acceptance is
claimed here.


### Initial integrated native author check

Author native XCTest **143/143 PASS**, zero failures, suite 5.798 seconds, elapsed
21.840 seconds, exit 0. Evidence root: `/private/tmp/rq-us3-author-qvlurq6m/`;
`native-command.json`, `native-result.json` and `native.log` retain the invocation
and outcome. Full Xcode 26.3 / Apple Swift 6.2.4 ran `swift test --disable-sandbox`
with isolated scratch/cache/config/security below that root. The 40 package/source
and test file hashes were captured after that run in `native-source-sha256.json`.
Core/Presentation and the lead-owned durable/session/editor extensions are frozen
for review or runtime feedback; parallel UI work does not establish iOS acceptance.

The root-created isolated author iPhone 17 device
`447AABA8-77C6-4E8B-B74D-58B326948828` booted successfully (bootstatus 25.395 seconds),
actual runtime iOS 26.3.1 build 23D8133. `boot.log` / `boot-result.json` retain the
preparation. No app/UI result is inferred from booting. Root owns its later cleanup
and records device provenance in `/private/tmp/returnqueue-us3-author-device.json`.

The [US3 native mapping](../../docs/design/us3-native-mapping.md) records five design
references, exact six SVG assets and platform adaptations; visual acceptance is
still pending. T009–T011 remain unchecked until final source review, independent
runtime and root acceptance.


### Initial iOS author run: acceptance blocked

Initial unsigned generic Simulator Debug and generic iOS Release builds passed
(exit 0; elapsed 15.461 and 18.790 seconds). The first complete author UI run
returned **FAIL**, exit 65: eight tests, four failures, suite 444.715 seconds,
elapsed 475.557 seconds. The existing recovery test could not observe native share
dismissal after tapping Close. All three new US3 journeys encountered a nested
accessibility alias when globally locating `refund.confirm`; actual hierarchy shows
one alert and two same-frame, same-label button representations. The four other
accepted UI scenarios passed. Evidence remains in `ui.log`, `ui-result.json`,
`UIResults.xcresult` and exported `attachments/manifest.json` below the author root.

`failed-ui-disk-proof.json` preserves eight isolated UUID roots. Recovery's original
36-byte corrupt file remained unchanged; its valid backup remained available, and
the still-owned temporary raw copy was byte-equal to that original. Cleanup had not
been reached. This failed run does not establish clean recovery completion.

The test owner narrowed only the new US3 confirmation helper to one active alert,
checking labels and identical nonzero frames before selecting the alias. Accepted
five tests and helpers, including the recovery dismissal assertion, remain unchanged.
Root authorized a separate native-share lifecycle experiment: native activity
completion/cancellation explicitly clears only its matching SwiftUI presentation;
existing cleanup still runs exclusively from sheet dismissal and retains ownership
until removal succeeds. Targeted recovery, final full eight tests and independent
acceptance remain pending; T009–T011 are still unchecked.


The approved lifecycle correction compiled in both unsigned configurations (Debug
10.219 seconds, Release 11.869 seconds, exit 0). The **unchanged** existing recovery
scenario then passed 1/1 with zero failures: suite 34.464 seconds, elapsed 44.037
seconds, exit 0. Actual native Close now led to owned-copy cleanup, explicit Retry
and the same restored saved item. Evidence: `lifecycle-{debug,release,recovery}`
command/result JSONs and logs, `LifecycleRecovery.xcresult`, and before/after source
manifests in the author evidence root. The complete final eight-case run is still
pending; this focused pass does not replace it or independent acceptance.


The subsequent complete UI attempt was stopped by root after identifying an explicit
deletion-confirmation context mismatch in the new test helper. It returned exit 73,
`TEST INTERRUPTED`, elapsed 120.653 seconds; `final-ui-abort.json` records the owned
process and reason. It is **not** a full-suite PASS. Product/source ownership is
frozen while the independent test author fixes that context.

Explicit local `tooling/harness.py verify` passed eight offline checks plus all
143 native tests, zero failures, native suite 5.875 seconds, elapsed 24.772 seconds,
exit 0. `harness-command.json`, `harness-result.json` and `harness.log` preserve
Swift 6.2.4, full Xcode, `CI` unset and explicit local sandbox opt-in. The partial
handoff has 85 frozen source fingerprints with zero mismatches; complete final UI8,
final distinct review, fresh independent QA and root acceptance are still required.

### US3 resumed independent checks — 2026-10-10, acceptance still blocked

After resuming, checks were repeated with durable evidence outside the worktree:
`../evidence/us3-2026-10-10/` relative to this checkout. Older temporary evidence
paths above are historical provenance; some plain logs/manifests under `/private/tmp`
were no longer present after the pause. They are not used as fresh acceptance proof.
The resumed source review recorded 85 fingerprints, including the app, package,
assets and tests; before/after hashes matched throughout each check below.

Independent native XCTest passed **143/143** (70 Core, 34 Storage, 39 Presentation),
zero failures/skips, suite 5.608 seconds. The required local harness passed eight
offline checks plus 143 native tests, exit 0, elapsed 15.55 seconds. Unsigned generic
Simulator Debug and iOS Release builds passed, elapsed 17.11 and 20.59 seconds.
Spec Kit integration, foundation checks, recursive strict formatter, project plist,
shared scheme XML and diff checks passed. These results use Xcode 26.3 (17C529),
Apple Swift 6.2.4 and iOS SDK 26.2; they do not establish signed distribution.

The fresh independent complete UI run on a separate iPhone 17 simulator
`4805E7D5-369F-4E57-A182-4BC15A885688`, actual iOS **26.3.1** (23D8133), returned
**FAIL**, exit 65: six passed, two failed, zero skipped; XCTest suite 740.500 seconds,
command elapsed 776.45 seconds. All 85 source fingerprints still matched the
reviewed snapshot. Original five UI cases and their helpers remained byte-identical
to the previously accepted baseline. The failures are product lifecycle defects:

- The existing corrupt-load recovery case tapped native Close, but the activity
  sheet remained visible. The actual screenshot and accessibility hierarchy confirm
  the open sheet. Original corrupt data and its backup remained intact; the owned
  36-byte temporary copy was byte-equal to the original, but dismissal/cleanup and
  explicit Retry were not reached. This is not completed recovery acceptance.
- The correction journey successfully reopened to the Queue detail, then committed
  Keep with the $20.25 store-credit entry preserved. Its second activation of History
  displayed the root list instead of the same record's detail. The recording's last
  frame and logs confirm the missing detail. Deletion and final relaunch assertions
  were not reached in this failed run.

`verifier/verification-report.json`, `verification-report.md`, `ui-summary.json`,
`ui-tests.json`, `source-tested-final.json`, `native40-proof.json`, disk proof,
`FullUIResults.xcresult`, exported attachments and the correction recording frame
retain the complete independent evidence. A focused author correction/excess run
had passed 2/2 earlier that day; that narrower author result did not replace this
independent complete run. Bounded recovery-presentation and tab-navigation fixes
return through affected source review and fresh independent runtime checks.

Root additionally ran the existing manual partial-refund journey at the largest
standard text size (`extra-extra-extra-large`): **1/1 PASS**, zero failures, suite
160.572 seconds. All 85 source hashes matched; original `large` size was restored.
The proof wrapper failed after the successful test because app reinstallation changed
its data-container path. Root resolved the current container and reconstructed the
proof from the completed xcresult, immutable command/source manifest and actual disk;
the test was not repeated or counted as failed. `visual/result.json` records this
limitation. The resulting archive contains separate $50 money/$30 credit, expected
$100 and manual partial closure with the $20 explanation. Root inspected seven
actual form/list/detail screenshots with no layout findings; fresh Figma screenshots
and six asset hashes are recorded under `design/`. This focused visual check does
not complete T015 VoiceOver/full accessibility or physical-device verification.

T009–T011 remain unchecked until both defects are resolved and all affected gates
pass. No commit/push, full restore, P2 or release acceptance is claimed here.

The subsequent independent two-case check (`verifier-final/`) proved the corrected
navigation journey end to end: **1/1 PASS**, 174.638 seconds, including correction,
Keep, reimbursement deletion and relaunch. The recovery case still failed at the
native Close lookup (30.298 seconds). Its actual screenshot shows a compact native
popover inside a mostly blank outer SwiftUI sheet. The overall two-case result was
one pass and one failure; it does not establish complete UI acceptance. Original
corrupt bytes, the recovery copy and the valid backup remained intact.

A bounded presentation-style change passed source review and unsigned builds, but
the next independent recovery check (`verifier-acceptance/`) again failed at Close,
31.628 seconds. A temporary, content-free UIKit lifecycle trace then established
that the activity controller retained its custom popover presentation despite the
ordinary style setter; its presenter was nested inside a SwiftUI form-sheet host.
The trace is retained under `recovery-lifecycle-diagnosis/`; diagnostic logging was
removed from shipping source. A supported adaptive-presentation delegate also
passed source review/builds but failed the unchanged author recovery case, 31.590
seconds (`recovery-adaptation-fix/`). No failed result is counted as acceptance.
Root authorized a narrowly scoped presentation-owner correction: show the native
activity from the attached Root hierarchy, retaining identity and temporary-copy
ownership through actual native dismissal. Its review and runtime gates are pending.

The first direct-Root author check failed only the native Close lookup, 91.311
seconds (`recovery-root-owner-fix/`). Its screenshot shows the real native activity
popover over Root, with the unwanted blank outer sheet removed. A separate synthetic
app then compared plain UIKit activity presentation and baseline SwiftUI embedding
on the same owned simulator (`native-activity-probe/`). Plain UIKit had a unique
native `PopoverDismissRegion`, no `header.closeButton`; SwiftUI embedding had the
native Close button. In both probes a single native cancellation action removed the
actual shared-file caption. The two diagnostic probes completed in 18.182 seconds;
these observations are not product acceptance or additional product test counts.

Based on that actual system behavior, root narrowed its earlier byte-preservation
policy: the recovery test may adapt only its native cancellation selector to both
supported presentations. The other four baseline cases/helpers remain unchanged.
The warning, actual original-file receipt, actual activity disappearance, actionable
Retry, cleanup, original data and repaired-record checks must remain intact. A
reviewer also requires that an interrupted dismissal retain the owned copy. The
final product source/test review and complete independent eight-case run remain
pending; T009–T011 are still unchecked.

## US3 final acceptance — 2026-10-10

The final separate source/test review passed with no open findings. The native
activity is presented by the attached Root owner; matching actual dismissal clears
its identified intent before cleanup. A cancelled transition or visible/pending
share cannot release its copy. The recovery test uses the real native Close button
or the verified native popover dismissal region, then requires disappearance of
both the actual activity and original-file caption. Its warning, explicit Retry
and repaired-record assertions remain unchanged, as do all other seven methods
and existing helpers. Root's narrow test-selector decision and actual system probe
are preserved under `native-activity-probe/`; the probe is diagnostic only.

Final independent evidence is in
`../evidence/us3-2026-10-10/verifier-release-candidate/`. Its
`verification-report.json`, exact `source-tested-final.json` (85 files), commands,
logs, `FullUIResults.xcresult`, method results and disk/screenshot manifests are
retained. The report binds this final source to the separate review:

| Final path | SHA-256 |
| --- | --- |
| RootView.swift | `566b48c87e85ae7a62313b51f0bb5ce473113291bceefa2e4f2d22fbb3900abc` |
| RecoveryShareView.swift | `e846647837c85dfb059496151fd61112669bd0d392c8db0b7e27a85c18976fea` |
| ReturnDetailView.swift | `34f1313d40f835ae83a95eed1aa933aeb33f247c080eb28a202d14ddacd8748e` |
| ReturnQueueUITests.swift | `dcf367f60ec2d634b590fc7358a0b53d70f0b6a33ae9c7336889e0aafbea3471` |

Independent unsigned Debug and Release builds passed, 44.249 and 37.463 seconds
respectively. Spec Kit integration, foundation, strict recursive formatter, project
syntax, shared scheme and diff checks passed. Xcode 26.3 build 17C529, Swift 6.2.4
and iOS SDK 26.2 were selected per command. The fresh verifier-owned iPhone 17
simulator `585F71E7-CDC5-400A-976E-2A6CEEFCE58A` ran actual iOS 26.3.1/23D8133.

All **8/8 UI scenarios passed**, zero failures or skips, in a single complete run
without filtering, retries or parallel testing: suite 889.784 seconds, command
922.299 seconds, exit 0. Recovery passed in 44.327 seconds; the final correction,
Keep, deletion and relaunch journey passed in 193.961 seconds. This final run
supersedes the earlier failed runtime gates; those failures remain recorded above.

The independent **143/143 native tests** (70 Core, 34 Storage, 39 Presentation)
and **eight offline harness checks plus 143 native tests** are reused from
`verifier/` and `verifier-final/`. All 40 native source/test paths match exactly;
`native40-proof.json` and `prior-gates-reuse.json` record this provenance. These
are prior actual passing runs on unchanged code, not newly executed tests in the
release-candidate run.

The current app container was resolved after installation. Actual disk inspection
found eight isolated test roots and ten records, no production-default archive,
and zero remaining recovery-copy files. The repaired archive exactly equals the
test's valid original backup. Manual partial closure retains expected $100,
$50 money, $30 store credit, difference $20 and its explicit explanation. The
corrected item is kept with an empty ledger and retained closure history; the
excess case retains $40 credit after the failed $50 write. Original corrupt
fixture bytes remain preserved in the captured evidence.

The current live raw-copy observer timed out during its initial bounded container
lookup, before export. No test was repeated to obtain another observation. Current
live copy byte equality is therefore unavailable; prior actual raw-copy equality
is reused only with unchanged raw-export code and byte-identical Root.export()
provenance in `raw-copy-reuse-provenance.json`. The current native caption shows
the actual 36-byte original file, and the current final disk proves dismissal
cleanup and successful repair. These evidence limits remain explicit.

Root viewed fresh native recovery, separate totals, partial-closure detail and
History list images. Seven earlier extra-extra-extra-large form/list/detail
screenshots remain representative: 81 of 85 paths are unchanged, while the four
changes concern lifecycle/navigation and the native cancellation test selector.
`visual/final-layout-reuse-proof.json` and `visual/final-root-visual-review.json`
record the comparison. A minor count pluralization follow-up belongs to P1 polish;
there are no blocking layout findings. This is not maximum accessibility text size,
VoiceOver, physical-device protection, remote GitLab, signing or release proof.

T009–T011 are accepted; **11 of 28 tasks accepted, 17 open**. Full validated
backup/restore and deletion T012–T014 are next. Complete P1 accessibility/offline
checks, P2 and the real-user pilot remain open. Preparing their proposals outside
Git does not accept those tasks. Commit/push follows final documentation review
and exact staged-source checks by root.
