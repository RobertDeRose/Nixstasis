defmodule Nixstasis.Reporting.CustomReport do
  @moduledoc """
  Resource for persisted custom report definitions.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "custom_reports"
    repo Nixstasis.Repo
  end

  json_api do
    type "custom_report"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :config]
    end

    update :update do
      accept [:name, :config]
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :config, :map do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_name, [:name]
  end
end
