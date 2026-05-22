#!/bin/sh

set -eu

# GoReleaser's makeself integration requires a root-level startup script.
# With --target /, extraction overwrites managed files in-place.
# Run the post-install hook, then clean up transient root files that
# GoReleaser stages (package.lsm, this script itself).

/usr/libexec/nixstasis/postinstall.sh

# Remove transient files GoReleaser places at archive root.
rm -f /package.lsm /entrypoint.sh /cleanup.sh
