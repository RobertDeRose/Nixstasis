#!/usr/bin/env bash
set -euo pipefail

MAKESELF_VERSION="${MAKESELF_VERSION:-2.7.1}"
MAKESELF_TAG="${MAKESELF_TAG:-release-${MAKESELF_VERSION}}"
DEFAULT_MAKESELF_SHA256="42f51a114ff671623e689ac4b74c444e9fc5bf8906dd88c82dc9e04e0b3938d1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_DIR="${MAKESELF_INSTALL_DIR:-build/tools/makeself/bin}"
WORK_DIR="${MAKESELF_WORK_DIR:-build/tools/makeself/src}"
ARCHIVE="makeself-${MAKESELF_VERSION}.run"
URL="https://github.com/megastep/makeself/releases/download/${MAKESELF_TAG}/${ARCHIVE}"

fail() {
  echo "Error: $1" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d ' ' -f 1
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d ' ' -f 1
    return
  fi

  fail "sha256sum or shasum is required"
}

expected_sha256() {
  if [[ -n "${MAKESELF_SHA256:-}" ]]; then
    echo "$MAKESELF_SHA256"
    return
  fi

  if [[ "$MAKESELF_VERSION" == "2.7.1" ]]; then
    echo "$DEFAULT_MAKESELF_SHA256"
    return
  fi

  fail "MAKESELF_SHA256 is required when MAKESELF_VERSION changes"
}

ensure_verified_archive() {
  local archive_path="$1"
  local expected_sha256="$2"

  if [[ -f "$archive_path" ]]; then
    if [[ "$(sha256_file "$archive_path")" == "$expected_sha256" ]]; then
      echo "Using cached ${ARCHIVE}"
      return
    fi

    echo "Cached ${ARCHIVE} checksum mismatch; re-downloading" >&2
    rm -f "$archive_path"
  fi

  echo "Downloading ${URL}"
  curl -fsSL "$URL" -o "$archive_path"

  if [[ "$(sha256_file "$archive_path")" != "$expected_sha256" ]]; then
    rm -f "$archive_path"
    fail "checksum mismatch for ${ARCHIVE}"
  fi
}

cd "$CLIENT_DIR"

mkdir -p "$INSTALL_DIR" "$WORK_DIR"

tmp_archive="${WORK_DIR}/${ARCHIVE}"
expected_sha256="$(expected_sha256)"
ensure_verified_archive "$tmp_archive" "$expected_sha256"

rm -f "${INSTALL_DIR}/makeself" "${INSTALL_DIR}/makeself-header.sh"
rm -rf "${WORK_DIR}/makeself-${MAKESELF_VERSION}"
sh "$tmp_archive" --quiet --target "$WORK_DIR" --noexec

makeself_sh="${WORK_DIR}/makeself.sh"
if [[ -f "${WORK_DIR}/makeself-${MAKESELF_VERSION}/makeself.sh" ]]; then
  makeself_sh="${WORK_DIR}/makeself-${MAKESELF_VERSION}/makeself.sh"
fi

cp "$makeself_sh" "${INSTALL_DIR}/makeself"
cp "$(dirname "$makeself_sh")/makeself-header.sh" "${INSTALL_DIR}/makeself-header.sh"
chmod +x "${INSTALL_DIR}/makeself"

"${INSTALL_DIR}/makeself" --version
