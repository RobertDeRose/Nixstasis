defmodule Nixstasis.SystemSetting do
  @moduledoc """
  Resource for storing system-level configuration values.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "system_settings"
    repo Nixstasis.Repo
  end

  json_api do
    type "system_setting"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:key, :value]
    end

    update :update do
      accept [:value]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
    end

    attribute :value, :map do
      allow_nil? false
      default %{}
    end

    timestamps()
  end

  identities do
    identity :unique_key, [:key]
  end
end
