#!/usr/bin/env bash
set -euo pipefail

MAKESELF_VERSION="${MAKESELF_VERSION:-2.7.1}"
MAKESELF_TAG="${MAKESELF_TAG:-release-${MAKESELF_VERSION}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_DIR="${MAKESELF_INSTALL_DIR:-build/tools/makeself/bin}"
WORK_DIR="${MAKESELF_WORK_DIR:-build/tools/makeself/src}"
ARCHIVE="makeself-${MAKESELF_VERSION}.run"
URL="https://github.com/megastep/makeself/releases/download/${MAKESELF_TAG}/${ARCHIVE}"

cd "$CLIENT_DIR"

mkdir -p "$INSTALL_DIR" "$WORK_DIR"

if [[ -x "${INSTALL_DIR}/makeself" && -f "${INSTALL_DIR}/makeself-header.sh" ]]; then
  "${INSTALL_DIR}/makeself" --version >/dev/null
  exit 0
fi

tmp_archive="${WORK_DIR}/${ARCHIVE}"
echo "Downloading ${URL}"
curl -fsSL "$URL" -o "$tmp_archive"

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
