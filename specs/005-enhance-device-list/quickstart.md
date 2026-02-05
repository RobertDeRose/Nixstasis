# Quickstart: Enhance Device List View

**Branch**: `005-enhance-device-list` | **Date**: 2026-02-04

## Setup

1.  **Dependencies**:
    - Ensure `frps` is running and accessible (for testing SSH/PCP).
    - Ensure Postgres is running.

2.  **Migrations**:
    ```bash
    mix ecto.gen.migration add_device_fields
    # Edit migration to add ipv4_address, account_number, indices
    mix ecto.migrate
    ```

3.  **Seeds (Optional)**:
    - Use `priv/repo/seeds.exs` to generate dummy devices with varying `last_polled_at` times to test Online/Offline status.

## Running

1.  **Start Phoenix**:
    ```bash
    mix phx.server
    ```

2.  **Access Device List**:
    - Navigate to `/devices`.

3.  **Verify Features**:
    - **Filter/Sort**: Click column headers; use filter inputs.
    - **Status**: Check for Green/Red icons.
    - **Detail Modal**: Click a row. Modal should open.
    - **PCP Charts**: Tab to "Performance". Charts should render (mock data if no device connected).
    - **Terminal**: Tab to "Terminal". `xterm.js` should appear.

## Testing

1.  **Unit Tests**:
    ```bash
    mix test test/nixstasis/devices
    ```

2.  **Integration Tests**:
    ```bash
    mix test test/nixstasis_web/live/device_live_test.exs
    ```
