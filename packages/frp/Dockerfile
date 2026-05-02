ARG FRP_VERSION=0.68.1
FROM debian:bookworm-slim

ARG FRP_VERSION

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl tar && \
    rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)" && \
    case "$arch" in \
      amd64) frp_arch="amd64" ;; \
      arm64) frp_arch="arm64" ;; \
      *) echo "unsupported architecture: $arch" >&2; exit 1 ;; \
    esac && \
    asset="frp_${FRP_VERSION}_linux_${frp_arch}.tar.gz" && \
    base_url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}" && \
    curl -fsSL "$base_url/frp_sha256_checksums.txt" -o /tmp/frp_sha256_checksums.txt && \
    expected_sha="$(awk -v asset="$asset" '$2 == asset {print $1}' /tmp/frp_sha256_checksums.txt)" && \
    [ -n "$expected_sha" ] && \
    curl -fsSL "$base_url/$asset" -o /tmp/frp.tar.gz && \
    actual_sha="$(sha256sum /tmp/frp.tar.gz | awk '{print $1}')" && \
    [ "$actual_sha" = "$expected_sha" ] && \
    tar -xzf /tmp/frp.tar.gz -C /tmp && \
    install -m 0755 "/tmp/frp_${FRP_VERSION}_linux_${frp_arch}/frps" /usr/local/bin/frps && \
    rm -rf /tmp/frp.tar.gz /tmp/frp_sha256_checksums.txt "/tmp/frp_${FRP_VERSION}_linux_${frp_arch}"

EXPOSE 7000 8080 8081 2022

CMD ["frps", "-c", "/etc/frp/frps.toml"]
