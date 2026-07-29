defmodule Nixstasis.CommandCatalog.CatalogCommand do
  @moduledoc """
  Server-approved catalog command that may become a command-policy source.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_catalog_commands"
    repo Nixstasis.Repo

    custom_indexes do
      index [:name_key]
      index [:active]
      index [:category_slugs], using: "gin"
    end
  end

  json_api do
    type "command_catalog_command"
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :name,
        :display_name,
        :description,
        :category_slugs,
        :risk_notes,
        :install_guidance,
        :current_version,
        :active
      ]

      change Nixstasis.CommandAllowlists.Changes.NormalizeNameKey
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :display_name,
        :description,
        :category_slugs,
        :risk_notes,
        :install_guidance,
        :current_version,
        :active
      ]

      change Nixstasis.CommandAllowlists.Changes.NormalizeNameKey
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints match: ~r/^[a-z0-9_.-]+$/
      public? true
    end

    attribute :name_key, :string do
      allow_nil? false
      public? true
    end

    attribute :display_name, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      default ""
      public? true
    end

    attribute :category_slugs, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :risk_notes, :string do
      default ""
      public? true
    end

    attribute :install_guidance, :string do
      default ""
      public? true
    end

    attribute :current_version, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :active, :boolean do
      allow_nil? false
      default true
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :mappings, Nixstasis.CommandCatalog.PackageMapping do
      destination_attribute :catalog_command_id
      public? true
    end
  end

  identities do
    identity :unique_name_key, [:name_key]
  end
end
