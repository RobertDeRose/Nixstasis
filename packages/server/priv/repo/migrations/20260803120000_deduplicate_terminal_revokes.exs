defmodule Nixstasis.Repo.Migrations.DeduplicateTerminalRevokes do
  use Ecto.Migration

  def up do
    execute("""
    CREATE UNIQUE INDEX pending_commands_terminal_revoke_unique
    ON pending_commands (device_id, ((command_payload->'payload'->>'name')))
    WHERE command_payload->>'type' = 'ssh_revoke'
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS pending_commands_terminal_revoke_unique")
  end
end
