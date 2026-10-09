defmodule Nixstasis.Repo.Migrations.PersistRemoteAccessLeaseState do
  use Ecto.Migration

  def up do
    alter table(:devices) do
      add :remote_access_expires_at, :utc_datetime_usec
      add :remote_access_owner, :text
    end

    # Existing requested flags have no trustworthy expiry. Fail closed during
    # migration rather than carrying an unbounded authorization forward.
    execute("""
    UPDATE devices
    SET remote_access_requested = FALSE
    WHERE remote_access_requested = TRUE
    """)
  end

  def down do
    alter table(:devices) do
      remove :remote_access_owner
      remove :remote_access_expires_at
    end
  end
end
