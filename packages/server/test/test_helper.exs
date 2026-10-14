ExUnit.start()
# The lease manager restores leases in handle_continue at boot; a call cannot
# be served until that finishes, so this waits out the restore before the
# sandbox leaves :auto mode.
Nixstasis.Devices.sync_remote_access_leases()
Ecto.Adapters.SQL.Sandbox.mode(Nixstasis.Repo, :manual)
