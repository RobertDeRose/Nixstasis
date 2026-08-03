defmodule Nixstasis.Scripts.ScriptClientAction do
  @moduledoc """
  Per-client results for test and deployment actions.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "script_client_actions"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
      reference :script_test_run, on_delete: :delete
      reference :script_deployment_run, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:script_test_run_id]
      index [:script_deployment_run_id]
      index [:status]
      index [:kind]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :device_id,
        :script_test_run_id,
        :script_deployment_run_id,
        :kind,
        :status,
        :command_ref,
        :payload_ref,
        :payload,
        :result_payload,
        :delivered_at,
        :acknowledged_at,
        :failed_at
      ]
    end

    update :update do
      accept [
        :status,
        :command_ref,
        :payload_ref,
        :payload,
        :result_payload,
        :delivered_at,
        :acknowledged_at,
        :failed_at
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, Nixstasis.Types.ScriptClientActionKind do
      allow_nil? false
      public? true
    end

    attribute :status, Nixstasis.Types.ScriptClientActionStatus do
      allow_nil? false
      default :queued
      public? true
    end

    attribute :command_ref, :string do
      public? true
    end

    attribute :payload_ref, :string do
      public? true
    end

    attribute :payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :result_payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :delivered_at, :utc_datetime do
      public? true
    end

    attribute :acknowledged_at, :utc_datetime do
      public? true
    end

    attribute :failed_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
      public? true
    end

    belongs_to :script_test_run, Nixstasis.Scripts.ScriptTestRun do
      allow_nil? true
      public? true
    end

    belongs_to :script_deployment_run, Nixstasis.Scripts.ScriptDeploymentRun do
      allow_nil? true
      public? true
    end
  end
end
