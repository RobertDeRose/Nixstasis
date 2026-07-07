defmodule Nixstasis.CommandAllowlists.Category do
  @moduledoc """
  First-class category tag for grouping command entries.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_allowlist_categories"
    repo Nixstasis.Repo

    custom_indexes do
      index [:slug]
    end
  end

  json_api do
    type "command_allowlist_category"
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

  relationships do
    has_many :entry_categories, Nixstasis.CommandAllowlists.CommandEntryCategory
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
