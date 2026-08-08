defmodule Nixstasis.CommandAllowlists.CommandEntry do
  @moduledoc """
  Operator-managed command entry for future exec_cmd policy resolution.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "command_allowlist_entries"
    repo Nixstasis.Repo

    custom_indexes do
      index [:name_key]
      index [:archived_at]
    end
  end

  json_api do
    type "command_allowlist_entry"
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :command_path, :current_version, :archived_at]
      change Nixstasis.CommandAllowlists.Changes.NormalizeNameKey
    end

    update :update do
      require_atomic? false

      accept [:name, :description, :command_path, :current_version, :archived_at]
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

    attribute :description, :string do
      default ""
      public? true
    end

    attribute :command_path, :string do
      allow_nil? false
      constraints match: ~r/^\/[^\s;&|`$<>(){}\[\]*?!'\"]+$/
      public? true
    end

    attribute :current_version, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :archived_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :versions, Nixstasis.CommandAllowlists.CommandEntryVersion
    has_many :entry_categories, Nixstasis.CommandAllowlists.CommandEntryCategory

    has_many :assignment_sources, Nixstasis.CommandAllowlists.DevicePolicyAssignmentSource do
      destination_attribute :source_id
      filter expr(source_kind == "command_entry")
    end
  end

  identities do
    identity :unique_name_key, [:name_key]
  end
end
