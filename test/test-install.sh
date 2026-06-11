#!/usr/bin/env bash
#
# Integration test for scripts/install.sh.
#
# Exercises the install script the same way action.yml does: by setting the
# INPUT_* environment variables and faking the $GITHUB_OUTPUT / $GITHUB_PATH
# files a runner would provide. Runs locally (macOS/Linux) and in CI.
#
# Usage: test/test-install.sh [version]   (default: latest)

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install_sh="${here}/../scripts/install.sh"
want_version="${1:-latest}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

github_output="${workdir}/output"
github_path="${workdir}/path"
: > "$github_output"
: > "$github_path"

pass=0
fail=0
check() {
  if [ "$2" = "$3" ]; then
    echo "  ok   - $1"
    pass=$((pass + 1))
  else
    echo "  FAIL - $1 (expected '$3', got '$2')"
    fail=$((fail + 1))
  fi
}
check_nonempty() {
  if [ -n "$2" ]; then
    echo "  ok   - $1 ('$2')"
    pass=$((pass + 1))
  else
    echo "  FAIL - $1 (was empty)"
    fail=$((fail + 1))
  fi
}

echo "Running install.sh (version=${want_version})..."
echo "----------------------------------------------------------------"
INPUT_VERSION="$want_version" \
INPUT_INSTALL_DIR="${workdir}/bin" \
INPUT_TOKEN="${GITHUB_TOKEN:-}" \
GITHUB_OUTPUT="$github_output" \
GITHUB_PATH="$github_path" \
  bash "$install_sh"
echo "----------------------------------------------------------------"

# Pull the step outputs back out of the fake $GITHUB_OUTPUT file.
out_version="$(grep '^version=' "$github_output" | cut -d= -f2-)"
out_binpath="$(grep '^bin-path=' "$github_output" | cut -d= -f2-)"
path_entry="$(cat "$github_path")"

echo "Assertions:"
check_nonempty "version output is set" "$out_version"
check "bin-path output points at the binary" "$out_binpath" "${workdir}/bin/shippy"
check "install dir was appended to GITHUB_PATH" "$path_entry" "${workdir}/bin"

# Binary exists and is executable.
if [ -x "${workdir}/bin/shippy" ]; then
  check "binary exists and is executable" "yes" "yes"
else
  check "binary exists and is executable" "no" "yes"
fi

# Binary actually runs and reports the same version as the output.
runtime_version="$("${workdir}/bin/shippy" version 2>/dev/null | head -n1 | awk '{print $3}')"
check "binary runs and reports same version as output" "$runtime_version" "$out_version"

# When a concrete version was requested, the binary must report it.
if [ "$want_version" != "latest" ]; then
  check "reported version matches requested" "$runtime_version" "${want_version#v}"
fi

echo "----------------------------------------------------------------"
echo "Passed: ${pass}  Failed: ${fail}"
[ "$fail" -eq 0 ]
