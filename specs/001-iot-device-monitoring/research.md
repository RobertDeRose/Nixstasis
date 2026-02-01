# Research Findings: IoT Device Monitoring

**Date**: 2026-01-31
**Feature**: IoT Device Monitoring
**Status**: Complete

## 1. Version Compatibility

**Decision**: Target **Elixir 1.19.5+** (OTP 28) and **Phoenix 1.8+** with **LiveView 1.1**.
**Rationale**:

- Elixir 1.19.5 (OTP 28) was released Jan 9, 2026.
- Phoenix 1.8 was released in August 2025.
- LiveView 1.1 was released in July 2025.
These are the latest stable versions as of early 2026 and should be used for all new development.
**Alternatives**:
- *Older Stable*: Elixir 1.18/Phoenix 1.7 (rejected as outdated for new 2026 project).

## 2. DaisyUI Integration

**Decision**: Install via `npm` and configure via `tailwind.config.js`.
**Rationale**: Standard integration path for Phoenix 1.7+.
**Implementation**:

- `npm install -D daisyui` in assets.
- Add `require("daisyui")` to `assets/tailwind.config.js`.
- Optionally refactor core components to use daisyUI classes.

## 3. Dynamic Schema with Ecto (JSONB)

**Decision**: Use **Ecto Embedded Schemas** within a `jsonb` column, indexed with **GIN**.
**Rationale**:

- `embeds_one`/`embeds_many` allow validation via Changesets even for dynamic data.
- GIN indexes provide efficient querying for "searchable" keys inside the JSONB payload.
**Alternatives**:
- *Raw Map*: Harder to validate.
- *EAV Pattern*: Complex querying, poor performance at scale.

## 4. Caddy + FRP + Phoenix

**Decision**: Configure Phoenix Endpoint `check_origin` to trust the FRP domain.
**Rationale**: Phoenix WebSocket/LiveView connections verify the `Host` header. FRP tunnels originate from a different
               domain than localhost.
**Implementation**:

- `config :my_app, MyAppWeb.Endpoint, check_origin: ["https://*.frp.domain", ...]`
- Enable `longpoll: true` fallback for robust connectivity if WS fails over tunnel.
