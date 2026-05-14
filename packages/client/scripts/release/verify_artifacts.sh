#!/bin/sh

set -eu

DIST_DIR="${DIST_DIR:-dist}"
VERIFY_INSTALLERS="${VERIFY_INSTALLERS:-false}"

fail() {
  echo "$1" >&2
  exit 1
}

require_dir() {
  [ -d "$1" ] || fail "missing directory: $1"
}

require_file() {
  [ -f "$1" ] || fail "missing artifact: $1"
}

require_member() {
  members="$1"
  path="$2"

  printf '%s\n' "$members" | grep -Eq "^(\./|/)?${path}$" || fail "missing packaged path: $path"
}

list_deb_members() {
  if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb -c "$1" | awk '{print $NF}'
    return
  fi

  if command -v bsdtar >/dev/null 2>&1; then
    data_archive=$(bsdtar -tf "$1" | grep '^data\.tar\.')
    [ -n "$data_archive" ] || fail "missing data archive in deb: $1"

    case "$data_archive" in
      *.tar.gz) bsdtar -xOf "$1" "$data_archive" | tar -tzf - ;;
      *.tar.xz) bsdtar -xOf "$1" "$data_archive" | tar -tJf - ;;
      *.tar.zst) bsdtar -xOf "$1" "$data_archive" | tar --zstd -tf - ;;
      *.tar) bsdtar -xOf "$1" "$data_archive" | tar -tf - ;;
      *) fail "unsupported deb data archive: $data_archive" ;;
    esac
    return
  fi

  fail "dpkg-deb or bsdtar is required to inspect deb artifacts"
}

list_rpm_members() {
  if command -v rpm >/dev/null 2>&1; then
    rpm -qlp "$1"
    return
  fi

  if command -v bsdtar >/dev/null 2>&1; then
    bsdtar -tf "$1"
    return
  fi

  fail "rpm or bsdtar is required to inspect RPM artifacts"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
    return
  fi

  fail "sha256sum or shasum is required to verify installer manifests"
}

verify_installer_manifest() {
  extract_dir="$1"
  manifest="$extract_dir/artifacts.json"

  require_file "$manifest"

  python3 - "$manifest" "$extract_dir" <<'PY'
import json
import os
import sys

manifest_path = sys.argv[1]
extract_dir = sys.argv[2]

with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

for key in ("version", "arch", "build_date", "files"):
    if key not in manifest:
        raise SystemExit(f"manifest missing key: {key}")

if not isinstance(manifest["files"], list) or not manifest["files"]:
    raise SystemExit("manifest files must be a non-empty list")

required = {
    "nixstasis",
    "frpc",
    "frpc.toml",
    "config.example.yaml",
    "nixstasis-poll.service",
    "nixstasis-poll.path",
    "nixstasis-registration.service",
    "install.sh",
}
covered = set()

for entry in manifest["files"]:
    for key in ("path", "sha256", "mode"):
        if key not in entry:
            raise SystemExit(f"manifest file entry missing key: {key}")
    path = entry["path"]
    if os.path.isabs(path) or ".." in path.split(os.sep):
        raise SystemExit(f"manifest path must be relative and safe: {path}")
    if not os.path.isfile(os.path.join(extract_dir, path)):
        raise SystemExit(f"manifest path missing from installer: {path}")
    covered.add(path)

missing = sorted(required - covered)
if missing:
    raise SystemExit("manifest missing required paths: " + ", ".join(missing))
PY

  python3 - "$manifest" "$extract_dir" <<'PY'
import hashlib
import json
import os
import sys

manifest_path = sys.argv[1]
extract_dir = sys.argv[2]

with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

for entry in manifest["files"]:
    path = os.path.join(extract_dir, entry["path"])
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    if actual != entry["sha256"]:
        raise SystemExit(
            f"sha256 mismatch for {entry['path']}: expected {entry['sha256']}, got {actual}"
        )
PY
}

verify_installer_members() {
  extract_dir="$1"

  require_file "$extract_dir/install.sh"
  require_file "$extract_dir/nixstasis"
  require_file "$extract_dir/frpc"
  require_file "$extract_dir/frpc.toml"
  require_file "$extract_dir/config.example.yaml"
  require_file "$extract_dir/nixstasis-poll.service"
  require_file "$extract_dir/nixstasis-poll.path"
  require_file "$extract_dir/nixstasis-registration.service"
  verify_installer_manifest "$extract_dir"
}

verify_common_members() {
  members="$1"
  binary_path="$2"

  require_member "$members" "$binary_path"
  require_member "$members" "etc/nixstasis/frpc.toml"
  require_member "$members" "usr/share/nixstasis/config.example.yaml"
  require_member "$members" "usr/libexec/nixstasis/frpc"
}

require_dir "$DIST_DIR"

ARCHIVE_COUNT=0
for archive in "$DIST_DIR"/*.tar.gz; do
  require_file "$archive"
  ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
  case "$archive" in
    *nixstasis*) ;;
    *) fail "artifact name must use nixstasis naming: $archive" ;;
  esac
  verify_common_members "$(tar -tzf "$archive")" "nixstasis"
done
[ "$ARCHIVE_COUNT" -gt 0 ] || fail "no tar.gz artifacts found in $DIST_DIR"

DEB_COUNT=0
for package in "$DIST_DIR"/*.deb; do
  require_file "$package"
  DEB_COUNT=$((DEB_COUNT + 1))
  case "$package" in
    *nixstasis*) ;;
    *) fail "artifact name must use nixstasis naming: $package" ;;
  esac
  verify_common_members "$(list_deb_members "$package")" "usr/bin/nixstasis"
done
[ "$DEB_COUNT" -gt 0 ] || fail "no deb artifacts found in $DIST_DIR"

RPM_COUNT=0
for package in "$DIST_DIR"/*.rpm; do
  require_file "$package"
  RPM_COUNT=$((RPM_COUNT + 1))
  case "$package" in
    *nixstasis*) ;;
    *) fail "artifact name must use nixstasis naming: $package" ;;
  esac
  verify_common_members "$(list_rpm_members "$package")" "usr/bin/nixstasis"
done
[ "$RPM_COUNT" -gt 0 ] || fail "no rpm artifacts found in $DIST_DIR"

RUN_COUNT=0
for installer in "$DIST_DIR"/*.run; do
  [ -e "$installer" ] || continue
  RUN_COUNT=$((RUN_COUNT + 1))
  case "$installer" in
    *nixstasis*) ;;
    *) fail "installer name must use nixstasis naming: $installer" ;;
  esac

  (
    extract_dir=$(mktemp -d "${TMPDIR:-/tmp}/nixstasis-installer-verify.XXXXXX")
    trap 'rm -rf "$extract_dir"' EXIT HUP INT TERM
    sh "$installer" --noexec --target "$extract_dir" >/dev/null
    verify_installer_members "$extract_dir"
  )
done
if [ "$VERIFY_INSTALLERS" = true ]; then
  [ "$RUN_COUNT" -gt 0 ] || fail "no self-extracting installer artifacts found in $DIST_DIR"
fi
