defmodule Nixstasis.Scripts.ScriptValidationRun do
  @moduledoc """
  Validation results for rendered Stary scripts.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "script_validation_runs"
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
        :validated_at,
        :front_matter,
        :rendered_content,
        :error_type,
        :error_message,
        :details
      ]
    end

    update :update do
      accept [:status, :validated_at, :error_type, :error_message, :details]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, Nixstasis.Types.ScriptValidationStatus do
      allow_nil? false
      default :pending
      public? true
    end

    attribute :validated_at, :utc_datetime do
      public? true
    end

    attribute :front_matter, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :rendered_content, :string do
      allow_nil? false
      default ""
      public? true
    end

    attribute :error_type, :string do
      public? true
    end

    attribute :error_message, :string do
      public? true
    end

    attribute :details, :map do
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
  end
end
