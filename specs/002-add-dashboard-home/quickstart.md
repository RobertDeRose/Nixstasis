# Quickstart: IoT Dashboard Homepage

**Feature**: `002-add-dashboard-home`

## Viewing the Dashboard

1. **Start the Server**:
   ```bash
   mix phx.server
   ```

2. **Access Homepage**:
   - Open browser to `http://localhost:4000/`.
   - The dashboard is now the default landing page.

3. **Verify Real-time Updates**:
   - Open a second terminal.
   - Run a script to toggle a device status or create an alert (using `iex`):
     ```elixir
     # In iex -S mix
     Nixstasis.Devices.create_device(...) # Watch "Total Devices" increment
     ```
