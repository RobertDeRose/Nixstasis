#!/bin/sh

set -eu

./usr/libexec/nixstasis/postinstall.sh
rm -f \
  ./makeself-entrypoint.sh \
  ./package.lsm \
  ./usr/libexec/nixstasis/cleanup.sh \
  ./usr/libexec/nixstasis/postinstall.sh
