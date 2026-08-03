#!/bin/bash

set -euo pipefail

ensure_group() {
    local group="$1"

    if ! getent group "$group" >/dev/null; then
        groupadd --system "$group"
    fi
}

ensure_service_user() {
    if ! getent passwd nixstasis >/dev/null; then
        useradd --system --create-home --home-dir /var/lib/nixstasis \
            --shell /usr/sbin/nologin --gid nixstasis nixstasis
    else
        usermod --home /var/lib/nixstasis --shell /usr/sbin/nologin nixstasis
    fi
}

ensure_support_user() {
    if ! getent passwd nixstasis-support >/dev/null; then
        useradd --system --create-home --home-dir /var/lib/nixstasis-support \
            --shell /bin/bash --gid nixstasis-support nixstasis-support
    else
        usermod --home /var/lib/nixstasis-support --shell /bin/bash nixstasis-support
    fi
}

ensure_authority_user() {
    if ! getent passwd nixstasis-ssh-authority >/dev/null; then
        useradd --system --no-create-home --home-dir /var/lib/empty \
            --shell /usr/sbin/nologin --gid nixstasis-ssh nixstasis-ssh-authority
    else
        usermod --home /var/lib/empty --shell /usr/sbin/nologin \
            --gid nixstasis-ssh nixstasis-ssh-authority
    fi

    usermod --append --groups nixstasis-ssh nixstasis
    usermod --append --groups nixstasis-ssh nixstasis-ssh-authority
    usermod --lock nixstasis-ssh-authority
}

ensure_group nixstasis
ensure_group nixstasis-support
ensure_group nixstasis-ssh
ensure_service_user
ensure_support_user
ensure_authority_user

if [ ! -e /etc/nixstasis/config.yaml ]; then
    mkdir -p /etc/nixstasis
    echo "Installing default config to /etc/nixstasis/config.yaml"
    cp /usr/share/nixstasis/config.example.yaml /etc/nixstasis/config.yaml
fi

# The registration and polling services run as nixstasis. The directory is
# writable for the persisted command policy while configuration files remain
# root-owned and readable only by the service group.
install -d -m 0750 -o nixstasis -g nixstasis /etc/nixstasis
if [ -f /etc/nixstasis/config.yaml ]; then
    chown root:nixstasis /etc/nixstasis/config.yaml
    chmod 0640 /etc/nixstasis/config.yaml
fi
for state_file in /etc/nixstasis/id /etc/nixstasis/command-policy.json; do
    if [ -f "$state_file" ]; then
        chown nixstasis:nixstasis "$state_file"
        chmod 0600 "$state_file"
    fi
done

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

# The service owns the runtime directory; the authority account receives
# group-only access to the directory and the 0660 socket created by the poller.
install -d -m 0755 -o root -g root /run/sshd
install -d -m 0750 -o nixstasis -g nixstasis-ssh /run/nixstasis
chown root:root /usr/libexec/nixstasis/ssh-authorized-keys \
    /etc/ssh/sshd_config.d/nixstasis-support.conf
chmod 0755 /usr/libexec/nixstasis/ssh-authorized-keys
chmod 0644 /etc/ssh/sshd_config.d/nixstasis-support.conf

validate_and_reload_sshd() {
    local sshd_bin
    sshd_bin="$(command -v sshd || true)"
    if [ -z "$sshd_bin" ] && [ -x /usr/sbin/sshd ]; then
        sshd_bin=/usr/sbin/sshd
    fi
    [ -n "$sshd_bin" ] || return 0

    "$sshd_bin" -t

    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet sshd.service; then
            systemctl reload sshd.service
        elif systemctl is-active --quiet ssh.service; then
            systemctl reload ssh.service
        fi
    fi
}

validate_and_reload_sshd

if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload

    action=("enable")
    [[ -d /run/systemd/system/ ]] && action+=("--now")

    systemctl "${action[@]}" nixstasis-registration.service
    systemctl "${action[@]}" nixstasis-poll.path
fi
