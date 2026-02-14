defmodule Nixstasis.Repo.Migrations.CreateE2ERuns do
  use Ecto.Migration

  def up do
    create table(:e2e_runs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :suite_id, :text, null: false
      add :journey_ids, {:array, :text}, null: false, default: []
      add :environment_label, :text, null: false
      add :trigger_source, :text, null: false
      add :client_version, :text, null: false
      add :server_version, :text, null: false
      add :status, :text, null: false, default: "queued"
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :run_metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:e2e_runs, [:status])
    create index(:e2e_runs, [:environment_label])
    create index(:e2e_runs, [:suite_id])

    create table(:e2e_run_results, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :run_id, references(:e2e_runs, type: :uuid, on_delete: :delete_all), null: false
      add :journey_id, :text, null: false
      add :status, :text, null: false, default: "queued"
      add :failure_step, :text
      add :failure_reason, :text
      add :log_ref, :text
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :duration_ms, :bigint
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:e2e_run_results, [:run_id])
    create index(:e2e_run_results, [:journey_id])
    create index(:e2e_run_results, [:status])
  end

  def down do
    drop_if_exists index(:e2e_run_results, [:status])
    drop_if_exists index(:e2e_run_results, [:journey_id])
    drop_if_exists index(:e2e_run_results, [:run_id])
    drop table(:e2e_run_results)

    drop_if_exists index(:e2e_runs, [:suite_id])
    drop_if_exists index(:e2e_runs, [:environment_label])
    drop_if_exists index(:e2e_runs, [:status])
    drop table(:e2e_runs)
  end
end
