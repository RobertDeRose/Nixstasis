# Manual Verification Steps

1. Start server: `mix phx.server`
2. Visit `http://localhost:4000/`.
3. Verify:
   - "Overview" title present.
   - 4 stats cards visible (Total, Online, Pending, Active).
   - 4 large navigation buttons visible.
4. Test Navigation:
   - Click "Manage Devices" -> should go to `/devices`.
   - Click "Pending Approvals" -> should go to `/approvals`.
   - Click "View Alerts" -> should go to `/alerts`.
   - Click "Reports" -> should go to `/reports`.
5. Test Real-time Updates (requires db seeds/console):
   - In terminal: `iex -S mix`
   - `Phoenix.PubSub.broadcast(Nixstasis.PubSub, "devices", {:device_registered, %{}})`
   - Verify dashboard stats blink/update (mocked in current implementation until backend logic is connected to real DB counts).
