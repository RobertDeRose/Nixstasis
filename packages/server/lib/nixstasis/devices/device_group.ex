defmodule Nixstasis.Devices.DeviceGroup do
  @moduledoc """
  Operator-managed metadata for a manual device group.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain

  postgres do
    table "device_groups"
    repo Nixstasis.Repo

    custom_indexes do
      index [:archived_at]
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description]
      change Nixstasis.Devices.Changes.NormalizeGroupName
    end

    update :update do
      require_atomic? false
      accept [:name, :description, :archived_at]
      change Nixstasis.Devices.Changes.NormalizeGroupName
    end

    destroy :destroy do
      require_atomic? false
      change Nixstasis.Devices.Changes.EnsureArchivedGroup
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1
      public? true
    end

    attribute :name_key, :string do
      allow_nil? false
    end

    attribute :description, :string do
      default ""
      public? true
    end

    attribute :archived_at, :utc_datetime do
      public? true
    end

    timestamps()
  end

  relationships do
    has_many :memberships, Nixstasis.Devices.DeviceGroupMembership do
      destination_attribute :group_id
    end

    many_to_many :devices, Nixstasis.Devices.Device do
      through Nixstasis.Devices.DeviceGroupMembership
      source_attribute_on_join_resource :group_id
      destination_attribute_on_join_resource :device_id
    end
  end

  identities do
    identity :unique_name_key, [:name_key]
  end
end
