ARG FRP_VERSION=0.68.1
FROM debian:bookworm-slim

ARG FRP_VERSION

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl jq tar && \
    rm -rf /var/lib/apt/lists/*

COPY bin/download_frp.sh /usr/local/bin/download_frp.sh
COPY bin/frps-entrypoint.sh /usr/local/bin/frps-entrypoint.sh

RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      amd64) frp_arch="amd64" ;; \
      arm64) frp_arch="arm64" ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac && \
    VERSION="$FRP_VERSION" ARCH="$frp_arch" COMPRESS=false OUTPUT_DIR=/tmp/frp-bin \
      /usr/local/bin/download_frp.sh && \
    install -m 0755 /tmp/frp-bin/frps /usr/local/bin/frps && \
    rm -rf /tmp/frp-bin

EXPOSE 7000 8080 8081 2022

ENTRYPOINT ["/usr/local/bin/frps-entrypoint.sh"]
