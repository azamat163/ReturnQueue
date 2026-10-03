#!/usr/bin/env bash
set +x
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
source tooling/ci/release-common.sh
release_preflight

for variable_name in IOS_PROJECT IOS_SCHEME IOS_TEST_DESTINATION IOS_TEAM_ID IOS_BUNDLE_ID IOS_CERTIFICATE_SHA1 IOS_P12_PASSWORD; do
  require_variable "$variable_name"
done
require_file_variable IOS_DISTRIBUTION_P12_BASE64
require_file_variable IOS_PROVISIONING_PROFILE_BASE64
[[ $IOS_PROJECT == *.xcodeproj && -d $IOS_PROJECT ]] || fail "IOS_PROJECT must point to the checked-in .xcodeproj."
[[ $IOS_PROJECT != /* && $IOS_PROJECT != *..* ]] || fail "IOS_PROJECT must stay inside this repository."
git ls-files --error-unmatch "$IOS_PROJECT/project.pbxproj" >/dev/null 2>&1 || fail "The Xcode project must be committed."
[[ -f "$IOS_PROJECT/xcshareddata/xcschemes/$IOS_SCHEME.xcscheme" ]] || fail "Commit a shared scheme for this project."
git ls-files --error-unmatch "$IOS_PROJECT/xcshareddata/xcschemes/$IOS_SCHEME.xcscheme" >/dev/null 2>&1 || fail "The shared scheme must be committed."
[[ $IOS_TEST_DESTINATION == *"platform=iOS Simulator"* ]] || fail "IOS_TEST_DESTINATION must select an available iOS Simulator."
[[ $IOS_TEAM_ID =~ ^[A-Z0-9]{10}$ ]] || fail "Invalid IOS_TEAM_ID."
[[ $IOS_BUNDLE_ID =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || fail "Invalid IOS_BUNDLE_ID."
[[ $IOS_CERTIFICATE_SHA1 =~ ^[A-Fa-f0-9]{40}$ ]] || fail "IOS_CERTIFICATE_SHA1 must be a certificate fingerprint."
[[ ${CI_PIPELINE_IID:-} =~ ^[0-9]+$ ]] || fail "CI_PIPELINE_IID is required as the monotonically increasing build number."
[[ ! -e build/release ]] || fail "Release output already exists; use a fresh checkout."

python3 - "$IOS_PROJECT/xcshareddata/xcschemes/$IOS_SCHEME.xcscheme" <<'PY'
import sys
import xml.etree.ElementTree as ET
scheme = ET.parse(sys.argv[1]).getroot()
test_action = scheme.find("TestAction")
if test_action is None:
    raise SystemExit("The shared app scheme has no test action.")
testables = [node for node in test_action.findall("Testables/TestableReference") if node.get("skipped") != "YES"]
if not testables and not test_action.findall("TestPlans/TestPlanReference"):
    raise SystemExit("The shared app scheme must include app tests or an app test plan.")
PY
# Gate release on actual app tests before decoding or importing any signing credential.
xcodebuild -project "$IOS_PROJECT" -scheme "$IOS_SCHEME" -configuration Debug \
  -destination "$IOS_TEST_DESTINATION" -derivedDataPath .build/ios-test test \
  CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=6.0 IPHONEOS_DEPLOYMENT_TARGET=17.0

umask 077
signing_dir=$(mktemp -d "${TMPDIR:-/tmp}/return-queue-signing.XXXXXX")
keychain_path="$signing_dir/signing.keychain-db"
keychain_password=$(openssl rand -hex 32)
original_keychains=()
installed_profiles=()
search_list_changed=0
keychain_created=0
cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM
  set +eu
  if [[ $search_list_changed == 1 ]]; then
    if ! security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1; then
      echo "Failed to restore the keychain search list; destroy the ephemeral runner." >&2
      exit_status=1
    fi
  fi
  for installed_profile in "${installed_profiles[@]}"; do
    rm -f "$installed_profile" || exit_status=1
  done
  if [[ $keychain_created == 1 ]]; then
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || exit_status=1
  fi
  rm -rf "$signing_dir" || exit_status=1
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

python3 tooling/ci/decode-file.py "$IOS_DISTRIBUTION_P12_BASE64" "$signing_dir/distribution.p12"
python3 tooling/ci/decode-file.py "$IOS_PROVISIONING_PROFILE_BASE64" "$signing_dir/profile.mobileprovision"
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
profile_uuid=$(python3 tooling/ci/profile-options.py "$signing_dir/profile.plist" "$signing_dir/ExportOptions.plist" \
  --team "$IOS_TEAM_ID" --bundle "$IOS_BUNDLE_ID" --certificate "$IOS_CERTIFICATE_SHA1")

# Install only this profile in both Xcode cache locations; never replace a pre-existing file.
for profiles_dir in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  profile_path="$profiles_dir/$profile_uuid.mobileprovision"
  [[ ! -e $profile_path ]] || fail "A profile with this UUID already exists; use an isolated clean runner."
  mkdir -p "$profiles_dir"
  installed_profiles+=("$profile_path")
  cp "$signing_dir/profile.mobileprovision" "$profile_path"
done

security create-keychain -p "$keychain_password" "$keychain_path"
keychain_created=1
security set-keychain-settings -lut 3600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$signing_dir/distribution.p12" -k "$keychain_path" -P "$IOS_P12_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" >/dev/null
security find-identity -v -p codesigning "$keychain_path" > "$signing_dir/identities.txt"
python3 - "$signing_dir/identities.txt" "$IOS_CERTIFICATE_SHA1" <<'PY'
import re
import sys
from pathlib import Path
fingerprints = re.findall(r'\b[A-Fa-f0-9]{40}\b', Path(sys.argv[1]).read_text())
if sys.argv[2].upper() not in {value.upper() for value in fingerprints}:
    raise SystemExit("Configured valid signing identity is missing from the imported p12.")
PY
security list-keychains -d user > "$signing_dir/original-keychains.txt"
python3 - "$signing_dir/original-keychains.txt" > "$signing_dir/keychain-paths.txt" <<'PY'
import shlex
import sys
from pathlib import Path
paths = shlex.split(Path(sys.argv[1]).read_text())
if not paths:
    raise SystemExit("Cannot safely restore an empty keychain search list; configure the isolated runner user.")
print("\n".join(paths))
PY
while IFS= read -r existing_keychain; do
  original_keychains+=("$existing_keychain")
done < "$signing_dir/keychain-paths.txt"
search_list_changed=1
security list-keychains -d user -s "${original_keychains[@]}" "$keychain_path"

# The first target is a single iOS app without extensions. Add per-target profile mappings when that changes.
xcodebuild -project "$IOS_PROJECT" -scheme "$IOS_SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/release/ReturnQueue.xcarchive \
  -derivedDataPath .build/ios-release archive \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$IOS_TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$IOS_BUNDLE_ID" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  CODE_SIGN_IDENTITY="$IOS_CERTIFICATE_SHA1" \
  CURRENT_PROJECT_VERSION="$CI_PIPELINE_IID" MARKETING_VERSION="${CI_COMMIT_TAG#v}" \
  IPHONEOS_DEPLOYMENT_TARGET=17.0 SWIFT_VERSION=6.0 \
  "OTHER_CODE_SIGN_FLAGS=--keychain $keychain_path"
xcodebuild -exportArchive -archivePath build/release/ReturnQueue.xcarchive \
  -exportOptionsPlist "$signing_dir/ExportOptions.plist" -exportPath build/release/export
ipa_files=(build/release/export/*.ipa)
[[ ${#ipa_files[@]} == 1 && -f ${ipa_files[0]} ]] || fail "Expected exactly one exported IPA."
echo "Archive and IPA exported. No upload has been requested."
