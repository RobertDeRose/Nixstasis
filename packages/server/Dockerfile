ARG ELIXIR_BUILDER_VERSION=1.19.3-erlang-28.5-ubuntu-noble-20260410
ARG ELIXIR_BUILDER_IMAGE_DIGEST=sha256:c4bdaf053f036a0f679499f99ee6e9e7ef17248376f6880a95cae41f8234abfe
ARG DEBIAN_RUNNER_VERSION=bookworm-slim
ARG DEBIAN_RUNNER_IMAGE_DIGEST=sha256:f9c6a2fd2ddbc23e336b6257a5245e31f996953ef06cd13a59fa0a1df2d5c252

FROM hexpm/elixir:${ELIXIR_BUILDER_VERSION}@${ELIXIR_BUILDER_IMAGE_DIGEST} AS builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git nodejs npm && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && mix local.rebar --force

COPY server/mix.exs server/mix.lock ./
COPY server/config config
RUN mix deps.get --only prod
RUN mix deps.compile

COPY server/lib lib
COPY server/priv priv
COPY server/assets assets
COPY shared ../shared

RUN mix assets.deploy
RUN mix compile
RUN mix release

ARG DEBIAN_RUNNER_VERSION=bookworm-slim
ARG DEBIAN_RUNNER_IMAGE_DIGEST

FROM debian:${DEBIAN_RUNNER_VERSION}@${DEBIAN_RUNNER_IMAGE_DIGEST} AS runner

RUN apt-get update && \
    apt-get install -y --no-install-recommends libstdc++6 openssl ca-certificates openssh-client ncat && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --create-home --home-dir /app app

WORKDIR /app

ENV MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000

COPY --from=builder /app/_build/prod/rel/nixstasis ./
COPY server/bin ./bin

RUN chmod +x ./bin/migrate ./bin/server ./bin/wait-for-postgres && chown -R app:app /app

USER app

EXPOSE 4000

CMD ["/app/bin/server"]
