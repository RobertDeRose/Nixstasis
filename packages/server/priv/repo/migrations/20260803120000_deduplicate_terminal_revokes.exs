defmodule Nixstasis.Repo.Migrations.DeduplicateTerminalRevokes do
  use Ecto.Migration

  def up do
    execute(&deduplicate_existing_revokes/0)

    execute("""
    CREATE UNIQUE INDEX pending_commands_terminal_revoke_unique
    ON pending_commands (device_id, ((command_payload->'payload'->>'name')))
    WHERE command_payload->>'type' = 'ssh_revoke'
    """)
  end

  @doc false
  def deduplicate_existing_revokes(repo \\ repo()) do
    repo.query!("""
    DELETE FROM pending_commands AS older
    USING pending_commands AS newer
    WHERE older.command_payload->>'type' = 'ssh_revoke'
      AND newer.command_payload->>'type' = 'ssh_revoke'
      AND older.device_id = newer.device_id
      AND older.command_payload->'payload'->>'name' = newer.command_payload->'payload'->>'name'
      AND older.id <> newer.id
      AND (
        older.queued_at < newer.queued_at
        OR (older.queued_at = newer.queued_at AND older.id::text < newer.id::text)
      )
    """)

    :ok
  end

  def down do
    execute("DROP INDEX IF EXISTS pending_commands_terminal_revoke_unique")
  end
end
