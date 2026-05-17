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

verify_installer_members() {
  extract_dir="$1"

  [ ! -e "$extract_dir/nixstasis" ] || fail "installer must not contain root file: nixstasis"
  [ ! -e "$extract_dir/postinstall.sh" ] || fail "installer must not contain root file: postinstall.sh"
  require_file "$extract_dir/makeself-entrypoint.sh"
  require_file "$extract_dir/usr/bin/nixstasis"
  require_file "$extract_dir/usr/libexec/nixstasis/frpc"
  require_file "$extract_dir/usr/libexec/nixstasis/postinstall.sh"
  require_file "$extract_dir/usr/libexec/nixstasis/makeself-cleanup.sh"
  require_file "$extract_dir/usr/share/nixstasis/frpc.toml"
  require_file "$extract_dir/usr/share/nixstasis/config.example.yaml"
  require_file "$extract_dir/lib/systemd/system/nixstasis-poll.service"
  require_file "$extract_dir/lib/systemd/system/nixstasis-poll.path"
  require_file "$extract_dir/lib/systemd/system/nixstasis-registration.service"
  [ -x "$extract_dir/usr/bin/nixstasis" ] || fail "installer member is not executable: $extract_dir/usr/bin/nixstasis"
  [ -x "$extract_dir/usr/libexec/nixstasis/frpc" ] || fail "installer member is not executable: $extract_dir/usr/libexec/nixstasis/frpc"
}

verify_common_members() {
  members="$1"
  binary_path="$2"

  require_member "$members" "$binary_path"
  require_member "$members" "usr/share/nixstasis/frpc.toml"
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
for installer in "$DIST_DIR"/makeself/*/*/*.run; do
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
