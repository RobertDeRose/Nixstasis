defmodule Nixstasis.Repo.Migrations.AddLiveviewQueryIndexes do
  @moduledoc """
  Adds composite indexes for bounded LiveView reads and device telemetry retention.
  """

  use Ecto.Migration

  def up do
    create index(:telemetry_events, [:device_id, :timestamp], name: :telemetry_events_device_timestamp_index)

    create index(:alerts, [:status, :triggered_at], name: :alerts_status_triggered_at_index)

    create index(:script_versions, [:script_draft_id, :inserted_at], name: :script_versions_draft_inserted_at_index)

    create index(:script_validation_runs, [:script_draft_id, :inserted_at],
             name: :script_validation_runs_draft_inserted_at_index
           )

    create index(:script_test_runs, [:script_draft_id, :inserted_at], name: :script_test_runs_draft_inserted_at_index)

    create index(:script_deployment_runs, [:script_draft_id, :inserted_at],
             name: :script_deployment_runs_draft_inserted_at_index
           )

    create index(:script_client_actions, [:script_test_run_id, :inserted_at],
             name: :script_client_actions_test_inserted_at_index
           )

    create index(:script_client_actions, [:script_deployment_run_id, :inserted_at],
             name: :script_client_actions_deploy_inserted_at_index
           )

    create index(:command_policy_assignments, [:device_id, :revision],
             name: :command_policy_assignments_device_revision_index
           )

    create index(:command_policy_assignment_sources, [:source_kind, :source_id],
             name: :command_policy_assignment_sources_kind_source_index
           )

    create index(:command_policy_delivery_results, [:assignment_id, :reported_at],
             name: :command_policy_delivery_results_assignment_reported_at_index
           )

    create index(:devices, [:approval_status, :last_seen_at], name: :devices_approval_last_seen_at_index)
  end

  def down do
    drop index(:devices, [:approval_status, :last_seen_at], name: :devices_approval_last_seen_at_index)

    drop index(:command_policy_delivery_results, [:assignment_id, :reported_at],
           name: :command_policy_delivery_results_assignment_reported_at_index
         )

    drop index(:command_policy_assignment_sources, [:source_kind, :source_id],
           name: :command_policy_assignment_sources_kind_source_index
         )

    drop index(:command_policy_assignments, [:device_id, :revision],
           name: :command_policy_assignments_device_revision_index
         )

    drop index(:script_client_actions, [:script_deployment_run_id, :inserted_at],
           name: :script_client_actions_deploy_inserted_at_index
         )

    drop index(:script_client_actions, [:script_test_run_id, :inserted_at],
           name: :script_client_actions_test_inserted_at_index
         )

    drop index(:script_deployment_runs, [:script_draft_id, :inserted_at],
           name: :script_deployment_runs_draft_inserted_at_index
         )

    drop index(:script_test_runs, [:script_draft_id, :inserted_at], name: :script_test_runs_draft_inserted_at_index)

    drop index(:script_validation_runs, [:script_draft_id, :inserted_at],
           name: :script_validation_runs_draft_inserted_at_index
         )

    drop index(:script_versions, [:script_draft_id, :inserted_at], name: :script_versions_draft_inserted_at_index)

    drop index(:alerts, [:status, :triggered_at], name: :alerts_status_triggered_at_index)

    drop index(:telemetry_events, [:device_id, :timestamp], name: :telemetry_events_device_timestamp_index)
  end
end
