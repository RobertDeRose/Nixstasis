#!/bin/bash

set -euo pipefail

if [ ! -e /etc/nixstasis/config.yaml ]; then
    mkdir -p /etc/nixstasis
    echo "Installing default config to /etc/nixstasis/config.yaml"
    cp /usr/share/nixstasis/config.example.yaml /etc/nixstasis/config.yaml
fi

if ! getent passwd nixstasis >/dev/null; then
    useradd --system --create-home --home-dir /var/lib/nixstasis --shell /usr/sbin/nologin nixstasis
else
    usermod --home /var/lib/nixstasis nixstasis
fi

if ! getent passwd nixstasis-support >/dev/null; then
    useradd --system --create-home --home-dir /var/lib/nixstasis-support --shell /bin/bash nixstasis-support
else
    usermod --home /var/lib/nixstasis-support --shell /bin/bash nixstasis-support
fi

mkdir -p /var/lib/nixstasis/.ssh
chown -R nixstasis:nixstasis /var/lib/nixstasis
chmod 750 /var/lib/nixstasis
chmod 700 /var/lib/nixstasis/.ssh

mkdir -p /var/lib/nixstasis-support/.ssh /etc/sudoers.d
chown -R nixstasis-support:nixstasis-support /var/lib/nixstasis-support
chmod 750 /var/lib/nixstasis-support
chmod 700 /var/lib/nixstasis-support/.ssh
printf 'nixstasis-support ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/nixstasis-support
chmod 0440 /etc/sudoers.d/nixstasis-support

action=("enable")
[[ -d /run/systemd/system/ ]] && action+=("--now")

systemctl "${action[@]}" nixstasis-registration.service
systemctl "${action[@]}" nixstasis-poll.path
