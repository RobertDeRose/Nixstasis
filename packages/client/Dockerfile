# Build stage: compile the Go client
ARG GO_VERSION=1.26
FROM golang:${GO_VERSION}-bookworm AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download

COPY . .
ENV GOEXPERIMENT=jsonv2
RUN CGO_ENABLED=0 go build -o /nixstasis ./cmd/nixstasis

# Fetch frpc
ARG FRP_VERSION=0.68.1
ARG TARGETARCH
RUN set -eux; \
    curl -fsSL "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${TARGETARCH}.tar.gz" \
      -o /tmp/frpc.tar.gz && \
    tar -xzf /tmp/frpc.tar.gz -C /tmp && \
    cp "/tmp/frp_${FRP_VERSION}_linux_${TARGETARCH}/frpc" /frpc && \
    chmod 0755 /frpc && \
    rm -rf /tmp/frpc.tar.gz /tmp/frp_*

# Runtime stage: systemd + sshd + frpc + client
FROM ubuntu:noble-20260410

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
      systemd systemd-sysv \
      openssh-server \
      ca-certificates \
      dbus && \
    rm -rf /var/lib/apt/lists/* && \
    # Clean up unnecessary systemd units
    rm -f /lib/systemd/system/multi-user.target.wants/* && \
    rm -f /etc/systemd/system/*.wants/* && \
    rm -f /lib/systemd/system/local-fs.target.wants/* && \
    rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
    rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
    rm -f /lib/systemd/system/basic.target.wants/* && \
    rm -f /lib/systemd/system/anaconda.target.wants/* && \
    # Configure sshd
    mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    systemctl enable ssh

# Install frpc
COPY --from=builder /frpc /usr/libexec/nixstasis/frpc

# Install client binary
COPY --from=builder /nixstasis /usr/bin/nixstasis

# Install systemd units
COPY build/root-dir/lib/systemd/system/ /lib/systemd/system/

# Install default config
COPY build/root-dir/usr/share/nixstasis/ /usr/share/nixstasis/

# Create nixstasis user and directories
RUN useradd --system --create-home --home-dir /var/lib/nixstasis nixstasis && \
    mkdir -p /var/lib/nixstasis/.ssh && \
    chown -R nixstasis:nixstasis /var/lib/nixstasis && \
    chmod 700 /var/lib/nixstasis/.ssh

# Enable client services
RUN systemctl enable nixstasis-registration.service && \
    systemctl enable nixstasis-poll.path

VOLUME ["/sys/fs/cgroup"]
STOPSIGNAL SIGRTMIN+3

ENTRYPOINT ["/lib/systemd/systemd"]
