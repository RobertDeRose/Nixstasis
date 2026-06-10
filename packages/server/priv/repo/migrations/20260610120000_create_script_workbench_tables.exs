defmodule Nixstasis.Repo.Migrations.CreateScriptWorkbenchTables do
  @moduledoc """
  Creates persistence for Stary script drafts, versions, and run results.
  """

  use Ecto.Migration

  def up do
    create table(:script_drafts, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :status, :text, null: false, default: "draft"
      add :front_matter, :map, null: false, default: %{}
      add :body, :text, null: false, default: ""
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:script_drafts, [:name], name: "script_drafts_unique_name_index")
    create index(:script_drafts, [:status])

    create table(:script_versions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version, :text, null: false
      add :status, :text, null: false, default: "candidate"
      add :front_matter, :map, null: false, default: %{}
      add :body, :text, null: false, default: ""
      add :rendered_content, :text, null: false, default: ""
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :script_draft_id,
          references(:script_drafts,
            column: :id,
            name: "script_versions_script_draft_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
    end

    create index(:script_versions, [:script_draft_id])
    create index(:script_versions, [:status])
    create unique_index(:script_versions, [:script_draft_id, :version], name: "script_versions_unique_draft_version_index")

    create table(:script_validation_runs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :text, null: false, default: "pending"
      add :validated_at, :utc_datetime
      add :front_matter, :map, null: false, default: %{}
      add :rendered_content, :text, null: false, default: ""
      add :error_type, :text
      add :error_message, :text
      add :details, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :script_draft_id,
          references(:script_drafts,
            column: :id,
            name: "script_validation_runs_script_draft_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
      add :script_version_id,
          references(:script_versions,
            column: :id,
            name: "script_validation_runs_script_version_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
    end

    create index(:script_validation_runs, [:script_draft_id])
    create index(:script_validation_runs, [:script_version_id])
    create index(:script_validation_runs, [:status])

    create table(:script_test_runs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :text, null: false, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :target_device_ids, {:array, :uuid}, null: false, default: []
      add :command_payload, :map, null: false, default: %{}
      add :notes, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :script_draft_id,
          references(:script_drafts,
            column: :id,
            name: "script_test_runs_script_draft_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
      add :script_version_id,
          references(:script_versions,
            column: :id,
            name: "script_test_runs_script_version_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
    end

    create index(:script_test_runs, [:script_draft_id])
    create index(:script_test_runs, [:script_version_id])
    create index(:script_test_runs, [:status])

    create table(:script_deployment_runs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :text, null: false, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :target_device_ids, {:array, :uuid}, null: false, default: []
      add :command_payload, :map, null: false, default: %{}
      add :notes, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :script_draft_id,
          references(:script_drafts,
            column: :id,
            name: "script_deployment_runs_script_draft_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
      add :script_version_id,
          references(:script_versions,
            column: :id,
            name: "script_deployment_runs_script_version_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
    end

    create index(:script_deployment_runs, [:script_draft_id])
    create index(:script_deployment_runs, [:script_version_id])
    create index(:script_deployment_runs, [:status])

    create table(:script_client_actions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :kind, :text, null: false
      add :status, :text, null: false, default: "queued"
      add :command_ref, :text
      add :payload_ref, :text
      add :payload, :map, null: false, default: %{}
      add :result_payload, :map, null: false, default: %{}
      add :delivered_at, :utc_datetime
      add :acknowledged_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :updated_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :device_id,
          references(:devices,
            column: :id,
            name: "script_client_actions_device_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          ),
          null: false
      add :script_test_run_id,
          references(:script_test_runs,
            column: :id,
            name: "script_client_actions_script_test_run_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
      add :script_deployment_run_id,
          references(:script_deployment_runs,
            column: :id,
            name: "script_client_actions_script_deployment_run_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all
          )
    end

    create index(:script_client_actions, [:device_id])
    create index(:script_client_actions, [:script_test_run_id])
    create index(:script_client_actions, [:script_deployment_run_id])
    create index(:script_client_actions, [:status])
    create index(:script_client_actions, [:kind])
  end

  def down do
    drop_if_exists index(:script_client_actions, [:kind])
    drop_if_exists index(:script_client_actions, [:status])
    drop_if_exists index(:script_client_actions, [:script_deployment_run_id])
    drop_if_exists index(:script_client_actions, [:script_test_run_id])
    drop_if_exists index(:script_client_actions, [:device_id])
    drop table(:script_client_actions)

    drop_if_exists index(:script_deployment_runs, [:status])
    drop_if_exists index(:script_deployment_runs, [:script_version_id])
    drop_if_exists index(:script_deployment_runs, [:script_draft_id])
    drop table(:script_deployment_runs)

    drop_if_exists index(:script_test_runs, [:status])
    drop_if_exists index(:script_test_runs, [:script_version_id])
    drop_if_exists index(:script_test_runs, [:script_draft_id])
    drop table(:script_test_runs)

    drop_if_exists index(:script_validation_runs, [:status])
    drop_if_exists index(:script_validation_runs, [:script_version_id])
    drop_if_exists index(:script_validation_runs, [:script_draft_id])
    drop table(:script_validation_runs)

    drop_if_exists unique_index(:script_versions, [:script_draft_id, :version], name: "script_versions_unique_draft_version_index")
    drop_if_exists index(:script_versions, [:status])
    drop_if_exists index(:script_versions, [:script_draft_id])
    drop table(:script_versions)

    drop_if_exists index(:script_drafts, [:status])
    drop_if_exists unique_index(:script_drafts, [:name], name: "script_drafts_unique_name_index")
    drop table(:script_drafts)
  end
end
