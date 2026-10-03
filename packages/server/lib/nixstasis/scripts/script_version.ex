defmodule Nixstasis.Scripts.ScriptVersion do
  @moduledoc """
  Persisted script version records for validation and deployment.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "script_versions"
    repo Nixstasis.Repo

    references do
      reference :script_draft, on_delete: :delete
    end

    custom_indexes do
      index [:script_draft_id]
      index [:status]
      index [:version]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:script_draft_id, :version, :status, :front_matter, :body, :rendered_content]
    end

    update :update do
      accept [:version, :status, :front_matter, :body, :rendered_content]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :string do
      allow_nil? false
      public? true
    end

    attribute :status, Nixstasis.Types.ScriptVersionStatus do
      allow_nil? false
      default :candidate
      public? true
    end

    attribute :front_matter, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :body, :string do
      allow_nil? false
      default ""
      public? true
    end

    attribute :rendered_content, :string do
      allow_nil? false
      default ""
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :script_draft, Nixstasis.Scripts.ScriptDraft do
      allow_nil? false
      public? true
    end

    has_many :validation_runs, Nixstasis.Scripts.ScriptValidationRun
    has_many :test_runs, Nixstasis.Scripts.ScriptTestRun
    has_many :deployment_runs, Nixstasis.Scripts.ScriptDeploymentRun
  end
end
