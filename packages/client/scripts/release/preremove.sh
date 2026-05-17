#!/bin/bash

set -euo pipefail

action=("disable")
[[ -d /run/systemd/system/ ]] && action+=("--now")

systemctl "${action[@]}" nixstasis-registration.service
systemctl "${action[@]}" nixstasis-poll.path

if systemctl is-active nixstasis-poll.service &> /dev/null; then
  systemctl stop nixstasis-poll.service
fi
