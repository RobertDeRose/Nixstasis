#!/bin/bash
set -e

echo "Building and installing nixstasis binary..."
GOOS=linux GOARCH=amd64 make install
