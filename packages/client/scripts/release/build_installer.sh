#!/bin/sh

set -eu

DIST_DIR="${DIST_DIR:-dist}"
ARCH="${ARCH:-}"

fail() {
  echo "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: build_installer.sh --arch amd64|arm64 [--dist-dir dist]

Builds a Nixstasis self-extracting installer from GoReleaser output.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --arch)
      [ "$#" -gt 1 ] || fail "--arch requires a value"
      ARCH="$2"
      shift 2
      ;;
    --dist-dir)
      [ "$#" -gt 1 ] || fail "--dist-dir requires a value"
      DIST_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

case "$ARCH" in
  amd64|arm64) ;;
  *) fail "--arch must be amd64 or arm64" ;;
esac

command -v makeself >/dev/null 2>&1 || fail "makeself is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  fail "sha256sum or shasum is required"
}

file_mode() {
  mode=$(stat -c '%a' "$1" 2>/dev/null) && printf '%s' "$mode" && return
  stat -f '%Lp' "$1"
}

json_escape() {
  python3 -c "import json,sys; s=json.dumps(sys.argv[1]); print(s[1:-1],end='')" "$1"
}

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
cd "$ROOT_DIR/packages/client"

[ -d "$DIST_DIR" ] || fail "missing dist directory: $DIST_DIR"
[ -f "$DIST_DIR/metadata.json" ] || fail "missing GoReleaser metadata: $DIST_DIR/metadata.json"

VERSION=$(python3 - "$DIST_DIR/metadata.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    metadata = json.load(f)

print(metadata.get("version") or metadata.get("Version") or "")
PY
)
[ -n "$VERSION" ] || fail "metadata.json does not contain a version"

BINARY_PATH=$(python3 - "$DIST_DIR" "$ARCH" <<'PY'
import os
import sys

dist_dir, arch = sys.argv[1:]
candidates = []

for root, _, files in os.walk(dist_dir):
    if "nixstasis" not in files:
        continue
    rel_root = os.path.relpath(root, dist_dir)
    if rel_root.startswith(f"nixstasis_linux_{arch}"):
        candidates.append(os.path.join(root, "nixstasis"))

if len(candidates) != 1:
    raise SystemExit(
        f"expected one nixstasis linux/{arch} binary in {dist_dir}, found {len(candidates)}"
    )

print(candidates[0])
PY
)
[ -f "$BINARY_PATH" ] || fail "missing GoReleaser binary: $BINARY_PATH"

FRPC_PATH="build/root-dir/usr/libexec/nixstasis/frpc_$ARCH"
[ -f "$FRPC_PATH" ] || fail "missing staged frpc binary: $FRPC_PATH"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/nixstasis-installer.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT HUP INT TERM

STAGING_DIR="$TMP_DIR/staging"
mkdir -p "$STAGING_DIR"

install -m 0755 "$BINARY_PATH" "$STAGING_DIR/nixstasis"
install -m 0755 "$FRPC_PATH" "$STAGING_DIR/frpc"
install -m 0644 build/root-dir/usr/share/nixstasis/frpc.toml "$STAGING_DIR/frpc.toml"
install -m 0644 build/root-dir/usr/share/nixstasis/config.example.yaml "$STAGING_DIR/config.example.yaml"
install -m 0644 build/root-dir/lib/systemd/system/nixstasis-poll.service "$STAGING_DIR/nixstasis-poll.service"
install -m 0644 build/root-dir/lib/systemd/system/nixstasis-poll.path "$STAGING_DIR/nixstasis-poll.path"
install -m 0644 build/root-dir/lib/systemd/system/nixstasis-registration.service "$STAGING_DIR/nixstasis-registration.service"
install -m 0755 scripts/release/install.sh "$STAGING_DIR/install.sh"

BUILD_DATE=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
MANIFEST="$STAGING_DIR/artifacts.json"

{
  printf '{\n'
  printf '  "version": "%s",\n' "$(json_escape "$VERSION")"
  printf '  "arch": "%s",\n' "$(json_escape "$ARCH")"
  printf '  "build_date": "%s",\n' "$(json_escape "$BUILD_DATE")"
  printf '  "files": [\n'

  sep=""
  for file in nixstasis frpc frpc.toml config.example.yaml nixstasis-poll.service nixstasis-poll.path nixstasis-registration.service install.sh; do
    path="$STAGING_DIR/$file"
    printf '%s' "$sep"
    printf '    {"path": "%s", "sha256": "%s", "mode": "%s"}' \
      "$(json_escape "$file")" "$(sha256_file "$path")" "$(file_mode "$path")"
    sep=',
'
  done

  printf '\n  ]\n'
  printf '}\n'
} > "$MANIFEST"

OUTPUT="$DIST_DIR/nixstasis-$VERSION-linux-$ARCH.run"
makeself --nox11 "$STAGING_DIR" "$OUTPUT" "Nixstasis client $VERSION ($ARCH)" ./install.sh

echo "built $OUTPUT"
