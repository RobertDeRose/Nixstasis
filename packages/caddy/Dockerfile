ARG CADDY_VERSION=2.11.2
ARG CADDY_SECURITY_VERSION=v1.1.62

FROM caddy:${CADDY_VERSION}-builder AS builder

ARG CADDY_SECURITY_VERSION

RUN xcaddy build \
    --with github.com/greenpau/caddy-security@${CADDY_SECURITY_VERSION}

ARG CADDY_VERSION=2.11.2

FROM caddy:${CADDY_VERSION}

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
