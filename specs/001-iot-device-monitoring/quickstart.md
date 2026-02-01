# Quickstart: IoT Device Monitoring

## Prerequisites

- **Elixir**: 1.19.5+
- **Postgres**: 15+
- **Node.js**: 20+ (for assets)

## Setup

1. **Install Dependencies**:

    ```bash
    mix deps.get
    cd assets && npm install
    ```

2. **Database Setup**:

    ```bash
    mix ecto.setup
    ```

    *Note*: This runs migrations for `devices`, `telemetry_events`, `alert_rules`, `alerts`, `pending_commands`.

3. **Start Server**:

    ```bash
    mix phx.server
    ```

    Access Dashboard at `http://localhost:4000/dashboard`.

## Running with Caddy/FRP (Simulated)

To test the remote connectivity locally:

1. **Start FRP Server (mock)**:
    Ensure `frps` is running or simulated via `config/dev.exs` proxy settings.

2. **Configure Endpoint**:
    Set `PHX_HOST` and `PHX_CHECK_ORIGIN` if testing via a real tunnel.

    ```bash
    export PHX_HOST=myapp.frp.com
    mix phx.server
    ```

## Testing

- **Run all tests**: `mix test`
- **Run Contract Tests**: `mix test --only contract`
- **Simulate Device**:
    Use the included script `priv/repo/seeds/simulate_device.exs` to generate traffic:

    ```bash
    mix run priv/repo/seeds/simulate_device.exs
    ```
