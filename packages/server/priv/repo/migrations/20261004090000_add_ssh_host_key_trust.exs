defmodule Nixstasis.Repo.Migrations.AddSshHostKeyTrust do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add :ssh_host_key, :text
      add :ssh_host_key_pending, :text
      add :ssh_host_key_trusted_at, :utc_datetime_usec
      add :ssh_host_key_trusted_by, :text
      add :ssh_host_key_previous_fingerprint, :text
    end
  end
end
