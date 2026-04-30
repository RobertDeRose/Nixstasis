#!/bin/sh

set -eu

test -d dist
find dist -type f | grep -Eq 'nixstasis.*(deb|rpm|tar.gz)$'
