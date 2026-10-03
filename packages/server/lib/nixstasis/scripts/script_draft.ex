defmodule Nixstasis.Scripts.ScriptDraft do
  @moduledoc """
  Persisted script draft content and authoring state.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "script_drafts"
    repo Nixstasis.Repo

    custom_indexes do
      index [:status]
      index [:name]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :status, :front_matter, :body]
    end

    update :update do
      accept [:name, :status, :front_matter, :body]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :status, Nixstasis.Types.ScriptDraftStatus do
      allow_nil? false
      default :draft
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

    timestamps()
  end

  relationships do
    has_many :versions, Nixstasis.Scripts.ScriptVersion
    has_many :validation_runs, Nixstasis.Scripts.ScriptValidationRun
  end

  identities do
    identity :unique_name, [:name]
  end
end
