#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$repo_root"
command -v swift >/dev/null || { echo "Swift toolchain is required." >&2; exit 1; }
actual_version=$(swift --version)
expected_version=${SWIFT_VERSION:-6.2.1}
case "$actual_version" in
  *"Swift version $expected_version "*) ;;
  *) echo "Expected Swift $expected_version; select the pinned toolchain." >&2; exit 1 ;;
esac
swift format --version
swift_files=()
while IFS= read -r -d '' source_file; do
  swift_files+=("$source_file")
done < <(git ls-files -z --cached --others --exclude-standard -- '*.swift')
[[ ${#swift_files[@]} -gt 0 ]] || { echo "No Swift sources found." >&2; exit 1; }
swift format lint --strict --configuration .swift-format "${swift_files[@]}"
ci_cache="$repo_root/.build/ci-cache"
mkdir -p "$ci_cache/modules" "$ci_cache/packages" "$ci_cache/config" "$ci_cache/security"
export CLANG_MODULE_CACHE_PATH="$ci_cache/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$ci_cache/modules"
swiftpm_options=()
if [[ ${RQ_SWIFTPM_DISABLE_SANDBOX:-0} == 1 ]]; then
  [[ ${CI:-false} != true ]] || { echo "Sandbox bypass is local-only, not permitted in CI." >&2; exit 1; }
  swiftpm_options+=(--disable-sandbox)
fi
# Older macOS Bash treats expansion of an empty array as unset with nounset.
set +u
swift test --scratch-path .build/ci-core --cache-path "$ci_cache/packages" \
  --config-path "$ci_cache/config" --security-path "$ci_cache/security" "${swiftpm_options[@]}"
