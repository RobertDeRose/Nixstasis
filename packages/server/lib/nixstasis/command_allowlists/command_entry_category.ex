defmodule Nixstasis.CommandAllowlists.CommandEntryCategory do
  @moduledoc """
  Join record assigning a category tag to a command entry.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_allowlist_entry_categories"
    repo Nixstasis.Repo

    references do
      reference :command_entry, on_delete: :delete
      reference :category, on_delete: :delete
    end

    custom_indexes do
      index [:command_entry_id]
      index [:category_id]
    end
  end

  json_api do
    type "command_allowlist_entry_category"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:command_entry_id, :category_id]
    end
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :command_entry, Nixstasis.CommandAllowlists.CommandEntry do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end

    belongs_to :category, Nixstasis.CommandAllowlists.Category do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_entry_category, [:command_entry_id, :category_id]
  end
end
