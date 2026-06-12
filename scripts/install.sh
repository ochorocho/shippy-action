#!/usr/bin/env bash
#
# Installs the shippy binary from GitHub releases.
#
# Driven by environment variables (set by action.yml, but usable standalone):
#   INPUT_VERSION      Release tag ("v0.0.9", "0.0.9") or "latest". Default: latest
#   INPUT_INSTALL_DIR  Target directory for the binary. Default: $HOME/.shippy/bin
#   INPUT_TOKEN        GitHub token for the releases API (optional, avoids rate limits)
#
# On a GitHub runner it appends to $GITHUB_PATH and writes the "version" and
# "bin-path" step outputs to $GITHUB_OUTPUT. Both are optional, so the script
# also runs locally for testing.

set -euo pipefail

REPO="ochorocho/shippy"
VERSION="${INPUT_VERSION:-latest}"
INSTALL_DIR="${INPUT_INSTALL_DIR:-}"
TOKEN="${INPUT_TOKEN:-}"

if [ -z "$INSTALL_DIR" ]; then
  INSTALL_DIR="${HOME}/.shippy/bin"
fi

# Emit a GitHub Actions error annotation when available, plain stderr otherwise.
fail() {
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::error::$1"
  else
    echo "Error: $1" >&2
  fi
  exit 1
}

# --- Detect OS -------------------------------------------------------------
os="$(uname -s)"
case "$os" in
  Linux) os="linux" ;;
  Darwin) os="darwin" ;;
  *) fail "Unsupported operating system '$os'. Shippy provides linux and darwin builds only." ;;
esac

# --- Detect architecture ---------------------------------------------------
arch="$(uname -m)"
case "$arch" in
  x86_64 | amd64) arch="amd64" ;;
  arm64 | aarch64) arch="arm64" ;;
  *) fail "Unsupported architecture '$arch'. Shippy provides amd64 and arm64 builds only." ;;
esac

# --- Build curl auth args --------------------------------------------------
auth=()
if [ -n "$TOKEN" ]; then
  auth=(-H "Authorization: Bearer ${TOKEN}")
fi

# --- Resolve "latest" to a concrete tag ------------------------------------
if [ "$VERSION" = "latest" ]; then
  echo "Resolving latest shippy release..."
  api="https://api.github.com/repos/${REPO}/releases/latest"
  if ! response="$(curl -sSfL "${auth[@]+"${auth[@]}"}" "$api")"; then
    fail "Could not reach the GitHub releases API at ${api}."
  fi
  VERSION="$(printf '%s\n' "$response" | awk -F'"' '/"tag_name"/{print $4; exit}')"
  if [ -z "$VERSION" ]; then
    fail "Could not resolve the latest shippy release from ${api}."
  fi
fi

# Normalize to a leading "v" so "0.0.9" and "v0.0.9" both work.
case "$VERSION" in
  v*) ;;
  *) VERSION="v${VERSION}" ;;
esac

asset="shippy-${os}-${arch}"
base="https://github.com/${REPO}/releases/download/${VERSION}"

echo "Installing shippy ${VERSION} (${os}/${arch})..."

# --- Download binary and checksum ------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! curl -sSfL "${auth[@]+"${auth[@]}"}" -o "${tmp}/${asset}" "${base}/${asset}"; then
  fail "Failed to download ${base}/${asset}. Does version ${VERSION} exist?"
fi
if ! curl -sSfL "${auth[@]+"${auth[@]}"}" -o "${tmp}/${asset}.checksum" "${base}/${asset}.checksum"; then
  fail "Failed to download checksum ${base}/${asset}.checksum."
fi

# --- Verify checksum -------------------------------------------------------
# The checksum file is either a bare hex digest (older releases) or the standard
# "<digest>  <filename>" sha256sum format (newer releases). Take the first field
# so both work.
expected="$(awk '{print $1; exit}' "${tmp}/${asset}.checksum")"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${tmp}/${asset}" | awk '{print $1}')"
else
  actual="$(shasum -a 256 "${tmp}/${asset}" | awk '{print $1}')"
fi

if [ -z "$expected" ]; then
  fail "Checksum file for ${asset} was empty."
fi
if [ "$expected" != "$actual" ]; then
  fail "Checksum mismatch for ${asset} (expected ${expected}, got ${actual})."
fi
echo "Checksum verified: ${actual}"

# --- Install ----------------------------------------------------------------
mkdir -p "$INSTALL_DIR"
mv "${tmp}/${asset}" "${INSTALL_DIR}/shippy"
chmod +x "${INSTALL_DIR}/shippy"

# --- Expose on PATH for subsequent steps -----------------------------------
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$INSTALL_DIR" >> "$GITHUB_PATH"
fi
export PATH="${INSTALL_DIR}:${PATH}"

# --- Verify the binary runs and capture the reported version ---------------
version_output="$("${INSTALL_DIR}/shippy" version 2>/dev/null || true)"
installed="$(printf '%s\n' "$version_output" | awk 'NR==1{print $3; exit}')"
if [ -z "$installed" ]; then
  fail "shippy was installed but did not report a version. The download may be corrupt."
fi

echo "Installed shippy ${installed} -> ${INSTALL_DIR}/shippy"

# --- Step outputs -----------------------------------------------------------
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "version=${installed}"
    echo "bin-path=${INSTALL_DIR}/shippy"
  } >> "$GITHUB_OUTPUT"
fi
