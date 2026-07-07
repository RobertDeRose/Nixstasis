defmodule Nixstasis.CommandAllowlists.CommandEntryVersion do
  @moduledoc """
  Immutable snapshot of a command entry at a security-relevant version.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_allowlist_entry_versions"
    repo Nixstasis.Repo

    references do
      reference :command_entry, on_delete: :delete
    end

    custom_indexes do
      index [:command_entry_id]
      index [:version]
      index [:name_key]
    end
  end

  json_api do
    type "command_allowlist_entry_version"
  end

  actions do
    defaults [:read]

    create :create do
      accept [:command_entry_id, :version, :name, :description, :command_path, :archived_at]
      change Nixstasis.CommandAllowlists.Changes.NormalizeNameKey
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :version, :integer do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :name_key, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      default ""
      public? true
    end

    attribute :command_path, :string do
      allow_nil? false
      public? true
    end

    attribute :archived_at, :utc_datetime do
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :command_entry, Nixstasis.CommandAllowlists.CommandEntry do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_entry_version, [:command_entry_id, :version]
  end
end
