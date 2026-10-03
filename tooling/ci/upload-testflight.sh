#!/usr/bin/env bash
set +x
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
source tooling/ci/release-common.sh
release_preflight
[[ ${TESTFLIGHT_UPLOAD_ENABLED:-0} == 1 ]] || fail "Set TESTFLIGHT_UPLOAD_ENABLED=1 to authorize this manual upload job."
require_variable ASC_KEY_ID
require_variable ASC_ISSUER_ID
require_file_variable ASC_PRIVATE_KEY
[[ $ASC_KEY_ID =~ ^[A-Z0-9]{10}$ ]] || fail "Invalid ASC_KEY_ID."
[[ $ASC_ISSUER_ID =~ ^[A-Fa-f0-9-]{36}$ ]] || fail "Invalid ASC_ISSUER_ID."
ipa_files=(build/release/export/*.ipa)
[[ ${#ipa_files[@]} == 1 && -f ${ipa_files[0]} ]] || fail "Expected exactly one IPA from the archive job in this pipeline."

umask 077
upload_dir=$(mktemp -d "${TMPDIR:-/tmp}/return-queue-upload.XXXXXX")
cleanup() {
  local exit_status=$?
  trap - EXIT INT TERM
  rm -rf "$upload_dir" || exit_status=1
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$upload_dir/keys"
cp "$ASC_PRIVATE_KEY" "$upload_dir/keys/AuthKey_$ASC_KEY_ID.p8"
export API_PRIVATE_KEYS_DIR="$upload_dir/keys"

# Use the installed Xcode tool's interface; fail instead of guessing when a toolchain changes it.
xcrun altool --help > "$upload_dir/altool-help.txt" 2>&1
for option in --validate-app --upload-app --apiKey --apiIssuer; do
  grep -q -- "$option" "$upload_dir/altool-help.txt" || fail "Installed altool changed its interface; review upload flags before using this Xcode."
done
xcrun altool --validate-app -f "${ipa_files[0]}" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
xcrun altool --upload-app -f "${ipa_files[0]}" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
echo "Upload command succeeded. Check App Store Connect processing before assigning TestFlight testers."
