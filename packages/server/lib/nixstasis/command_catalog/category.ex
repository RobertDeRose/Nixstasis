defmodule Nixstasis.CommandCatalog.Category do
  @moduledoc """
  Server-curated command catalog category.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_catalog_categories"
    repo Nixstasis.Repo

    custom_indexes do
      index [:slug]
    end
  end

  json_api do
    type "command_catalog_category"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:slug, :display_name, :description]
      change Nixstasis.CommandAllowlists.Changes.NormalizeSlug
    end

    update :update do
      require_atomic? false

      accept [:slug, :display_name, :description]
      change Nixstasis.CommandAllowlists.Changes.NormalizeSlug
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :slug, :string do
      allow_nil? false
      constraints match: ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
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

    timestamps()
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
