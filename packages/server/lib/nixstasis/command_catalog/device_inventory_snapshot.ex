defmodule Nixstasis.CommandCatalog.DeviceInventorySnapshot do
  @moduledoc """
  Latest untrusted command/package inventory evidence reported by a managed device.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "device_command_inventory_snapshots"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
    end

    custom_indexes do
      index [:device_id]
      index [:probe_catalog_version]
      index [:observed_at]
      index [:os_family]
      index [:packages], using: "gin"
      index [:commands], using: "gin"
    end
  end

  json_api do
    type "device_command_inventory_snapshot"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :device_id,
        :schema_version,
        :probe_catalog_version,
        :observed_at,
        :architecture,
        :os_release,
        :os_family,
        :package_manager,
        :packages,
        :commands
      ]

      upsert? true
      upsert_identity :unique_device_snapshot

      upsert_fields [
        :schema_version,
        :probe_catalog_version,
        :observed_at,
        :architecture,
        :os_release,
        :os_family,
        :package_manager,
        :packages,
        :commands
      ]

      change Nixstasis.CommandCatalog.Changes.NormalizeInventory
    end

    update :update do
      require_atomic? false

      accept [
        :schema_version,
        :probe_catalog_version,
        :observed_at,
        :architecture,
        :os_release,
        :os_family,
        :package_manager,
        :packages,
        :commands
      ]

      change Nixstasis.CommandCatalog.Changes.NormalizeInventory
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :schema_version, :integer do
      allow_nil? false
      public? true
    end

    attribute :probe_catalog_version, :string do
      allow_nil? false
      public? true
    end

    attribute :observed_at, :utc_datetime do
      allow_nil? false
      public? true
    end

    attribute :architecture, :string do
      allow_nil? false
      public? true
    end

    attribute :os_release, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :os_family, :string do
      public? true
    end

    attribute :package_manager, :string do
      allow_nil? false
      public? true
    end

    attribute :packages, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :commands, :map do
      allow_nil? false
      default %{}
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
      public? true
      attribute_public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_device_snapshot, [:device_id]
  end
end
