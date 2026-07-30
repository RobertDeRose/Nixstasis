defmodule Nixstasis.Devices.DeviceGroupMembership do
  @moduledoc """
  Many-to-many membership between a device and a manual device group.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "device_group_memberships"
    repo Nixstasis.Repo

    references do
      reference :device, on_delete: :delete
      reference :group, on_delete: :restrict
    end

    custom_indexes do
      index [:group_id]
      index [:device_id]
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:group_id, :device_id]
    end
  end

  attributes do
    uuid_primary_key :id
    timestamps()
  end

  relationships do
    belongs_to :group, Nixstasis.Devices.DeviceGroup do
      allow_nil? false
      attribute_public? true
      attribute_writable? true
    end

    belongs_to :device, Nixstasis.Devices.Device do
      allow_nil? false
      attribute_public? true
      attribute_writable? true
    end
  end

  identities do
    identity :unique_group_device, [:group_id, :device_id]
  end
end
