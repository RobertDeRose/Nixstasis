defmodule Nixstasis.Repo.Migrations.HardenE2EContracts do
  use Ecto.Migration

  def up do
    alter table(:e2e_runs) do
      add :protocol_version, :text, null: false, default: "1"
      add :idempotency_key, :text
      add :idempotency_expires_at, :utc_datetime_usec
      remove :client_version
      remove :server_version
    end

    create index(:e2e_runs, [:environment_label, :idempotency_key, :idempotency_expires_at],
             name: :e2e_runs_idempotency_idx
           )

    create table(:e2e_environment_locks, primary_key: false) do
      add :environment_label, :text, primary_key: true
      add :run_id, references(:e2e_runs, type: :uuid, on_delete: :delete_all)
      add :locked_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:e2e_environment_locks, [:run_id],
             where: "run_id IS NOT NULL",
             name: :e2e_environment_locks_run_id_idx
           )
  end

  def down do
    drop_if_exists unique_index(:e2e_environment_locks, [:run_id], name: :e2e_environment_locks_run_id_idx)
    drop table(:e2e_environment_locks)

    drop_if_exists index(:e2e_runs, [:environment_label, :idempotency_key, :idempotency_expires_at],
                     name: :e2e_runs_idempotency_idx
                   )

    alter table(:e2e_runs) do
      add :client_version, :text, null: false, default: "0.0.0"
      add :server_version, :text, null: false, default: "0.0.0"
      remove :protocol_version
      remove :idempotency_key
      remove :idempotency_expires_at
    end
  end
end
