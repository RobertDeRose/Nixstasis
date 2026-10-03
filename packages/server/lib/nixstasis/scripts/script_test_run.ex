defmodule Nixstasis.Scripts.ScriptTestRun do
  @moduledoc """
  Test run records for selected clients.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "script_test_runs"
    repo Nixstasis.Repo

    references do
      reference :script_draft, on_delete: :delete
      reference :script_version, on_delete: :delete
    end

    custom_indexes do
      index [:script_draft_id]
      index [:script_version_id]
      index [:status]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :script_draft_id,
        :script_version_id,
        :status,
        :started_at,
        :completed_at,
        :target_device_ids,
        :command_payload,
        :notes
      ]
    end

    update :update do
      accept [:status, :started_at, :completed_at, :command_payload, :notes]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, Nixstasis.Types.ScriptTestRunStatus do
      allow_nil? false
      default :pending
      public? true
    end

    attribute :started_at, :utc_datetime do
      public? true
    end

    attribute :completed_at, :utc_datetime do
      public? true
    end

    attribute :target_device_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
    end

    attribute :command_payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :notes, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :script_draft, Nixstasis.Scripts.ScriptDraft do
      allow_nil? false
      public? true
    end

    belongs_to :script_version, Nixstasis.Scripts.ScriptVersion do
      allow_nil? true
      public? true
    end

    has_many :client_actions, Nixstasis.Scripts.ScriptClientAction do
      destination_attribute :script_test_run_id
    end
  end

  calculations do
    calculate :target_device_count, :integer, expr(fragment("cardinality(?)", target_device_ids))
  end
end
