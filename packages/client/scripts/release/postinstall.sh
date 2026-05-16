#!/bin/bash

set -euo pipefail

if [ ! -e /etc/nixstasis/config.yaml ]; then
    mkdir -p /etc/nixstasis
    echo "Installing default config to /etc/nixstasis/config.yaml"
    cp /usr/share/nixstasis/config.example.yaml /etc/nixstasis/config.yaml
fi

action=("enable")
[[ -d /run/systemd/system/ ]] && action+=("--now")

systemctl "${action[@]}" nixstasis-registration.service
systemctl "${action[@]}" nixstasis-poll.path
