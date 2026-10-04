# iOS release setup

This is the configuration checklist for the prepared [GitLab pipeline](gitlab-ci.md).
All release jobs are off by default. No GitLab project, Apple app record, certificate,
profile, signing key, runner or public release was created by this harness work.

## Application prerequisites

- A checked-in iOS app `.xcodeproj` with a committed shared scheme, Release Archive
  configuration, Swift 6 language mode and iOS 17 deployment target. SwiftPM Core
  alone is insufficient. The initial signing harness supports one app target and
  no extensions; additional executable targets need their own profile mappings.
- Successful full-Xcode package tests and iOS simulator/device tests appropriate
  to the actual app. T007/T008 passed the current 106 native package tests, unsigned
  Simulator/Release builds and five UI scenarios on a fresh simulator. Broader P1/P2,
  physical-device checks and signed distribution are separate evidence; see feature verification.
- Apple Developer Program membership and a team that can distribute apps. Register
  the intended explicit Bundle ID and create the matching App Store Connect app
  record. Choose the Bundle ID before generating credentials.
- An Apple Distribution certificate with its private key exported as a password
  protected p12, and an unexpired App Store distribution provisioning profile for
  that exact Bundle ID, team and certificate. These are distinct from the App Store
  Connect API key used for upload.
- A stable Xcode 26 macOS runner and disposable isolated account/VM as described in
  [GitLab CI](gitlab-ci.md). Review current Apple's SDK/toolchain acceptance before
  shipping. Prepare local manual export once to confirm entitlements and capabilities.

## Non-secret GitLab variables

Release feature switches must be regular project/group variables available when
GitLab evaluates job rules. Do not give them an environment-specific scope: GitLab
warns that environment-scoped variables may be unavailable during rule evaluation.
Keep release switches protected and controlled by trusted maintainers.

| Variable | Meaning |
| --- | --- |
| `IOS_RELEASE_ENABLED` | `0` initially; `1` enables the manual archive job on protected version tags. |
| `TESTFLIGHT_UPLOAD_ENABLED` | `0` initially; `1` additionally enables the separate manual upload action. |
| `IOS_EPHEMERAL_RUNNER` | `1` only after disposable macOS VM isolation is established. A flag is not isolation. |
| `DEVELOPER_DIR` | Actual full-Xcode developer directory, e.g. `/Applications/Xcode_26.2.app/Contents/Developer`. |
| `XCODE_VERSION` | Exact installed version, e.g. `26.2`; this is an example, not an asserted latest release. |
| `IOS_PROJECT` | Committed `ReturnQueue.xcodeproj`, shared scheme includes UI tests. |
| `IOS_SCHEME` | К `ReturnQueue` уже подключены пять UI-тестов. Выбор тестового устройства на runner, подпись и полная приёмка релиза ещё требуются. |
| `IOS_TEST_DESTINATION` | Explicit available simulator destination, e.g. `platform=iOS Simulator,id=<installed-simulator-UUID>`. Select it after inspecting `xcrun simctl list devices available` on the runner. |
| `IOS_TEAM_ID` | The ten-character distribution team ID. |
| `IOS_BUNDLE_ID` | The explicit app Bundle ID, identical in the app record and provisioning profile. |
| `IOS_CERTIFICATE_SHA1` | Forty-character SHA1 fingerprint of the intended valid signing identity. |
| `ASC_KEY_ID` | Ten-character ID of the team's App Store Connect API upload key. |
| `ASC_ISSUER_ID` | Issuer UUID for that team API key. |

Do not paste the example values blindly. The script checks for missing or invalid
configuration before importing credentials. Tag `v0.1.0` supplies marketing version
`0.1.0`; GitLab's increasing `CI_PIPELINE_IID` supplies the build number. Keep the
same GitLab project for build-number continuity. Retrying an upload job after a
successful upload can cause a duplicate-build error; verify Apple processing first.
For a new binary, start a new pipeline so its build number increases.

## Secret variables

Create these in GitLab settings, never in a committed YAML, `.env`, skill, issue or
chat. Mark them **Protected**. Use **Masked and hidden** for the p12 password when
GitLab permits it. Multiline File contents may not qualify for masking; protected
scope and restricted runner access remain necessary. Scope release credentials to
environment `testflight` so the Linux validation job cannot read them.

| Variable | GitLab type | Contents |
| --- | --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | File | Base64 encoded Apple Distribution p12 bytes. |
| `IOS_P12_PASSWORD` | Variable | The strong password used when exporting that p12. |
| `IOS_PROVISIONING_PROFILE_BASE64` | File | Base64 encoded `.mobileprovision` bytes. |
| `ASC_PRIVATE_KEY` | File | PEM `.p8` private key for the configured App Store Connect team API key. |

GitLab's web UI stores File variables as text. Encode the p12 and provisioning
profile locally as base64 and put that text into the protected File variables.
The script decodes them into mode-600 files inside the temporary signing directory.
The `.p8` key is already PEM text and remains a plain File variable. Base64 is an
encoding, not encryption: protect its contents like the original credential.
Never paste encoded credentials into command logs or commit them. The decoder
fails on invalid input and refuses to overwrite an existing output. No actual
secret provisioning has been performed here.

The [profile validator](../tooling/ci/profile-options.py) checks the team, explicit
Bundle ID, distribution mode, expiry, iOS platform and included certificate.
The archive job also confirms that the imported p12 supplies the intended valid
codesigning identity. Apple's signing/export tools remain responsible for checking
actual entitlements, trust and signatures; this validator does not replace them.
Neither job changes provisioning profiles on Apple's server.

The upload script uses a temporary directory for `AuthKey_<key-id>.p8` through
`API_PRIVATE_KEYS_DIR`. It checks the installed `altool` interface and fails if the
pinned Xcode exposes different flags; review rather than silently changing upload
behavior. Do not enable shell tracing or `CI_DEBUG_TRACE` on signing/upload jobs.

## First release run

1. Complete app and runner prerequisites and validate the pipeline with GitLab CI
   Lint. Test the archive in the configured environment before relying on it.
2. Configure variables, protect `v*` tags and the release runner, and keep upload
   disabled. Create a version tag from a reviewed commit only when ready to archive.
3. Enable `IOS_RELEASE_ENABLED=1` and create a tag pipeline. After Foundation and Core checks pass,
   run `ios:archive` manually. It first runs the app simulator tests, then signs and
   exports. Inspect the archive/IPA, version and entitlements.
4. When ready to send this build to Apple, enable `TESTFLIGHT_UPLOAD_ENABLED=1` before
   creating the relevant pipeline and run its manual upload job. Switches are
   evaluated when the pipeline is created; an existing pipeline will not gain a
   previously excluded job just because the variable changed.
5. Check App Store Connect processing, resolve any export-compliance questions, and
   assign testers. External testing can require Beta App Review. Public App Store
   submission and release remain outside this pipeline.

Source guidance: [GitLab File/protected variables](https://docs.gitlab.com/ci/variables/),
[environment scopes and rule evaluation](https://docs.gitlab.com/ci/environments/),
[Apple signing workflow](https://help.apple.com/xcode/mac/current/en.lproj/dev60b6fbbc7.html),
[Apple upload prerequisites and processing](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/),
[Apple export-options guidance](https://developer.apple.com/library/archive/technotes/tn2339/_index.html).
