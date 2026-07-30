defmodule Nixstasis.DeviceGroupsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  describe "device group persistence" do
    test "normalizes names and reserves them across archived groups" do
      assert {:ok, group} =
               Domain.create_device_group(%{name: "  Warehouse Sensors  ", description: "North wing"})

      assert group.name == "Warehouse Sensors"
      assert group.name_key == "warehouse sensors"
      assert group.description == "North wing"

      device = device_fixture("10:22:33:44:55:66")

      assert {:ok, membership} =
               Domain.create_device_group_membership(%{
                 group_id: group.id,
                 device_id: device.id
               })

      assert {:ok, archived} =
               Domain.update_device_group(group, %{archived_at: DateTime.utc_now()})

      assert archived.archived_at
      assert Enum.map(Ash.load!(archived, :devices).devices, & &1.id) == [device.id]
      assert Enum.map(Ash.load!(device, :device_groups).device_groups, & &1.id) == [group.id]
      assert {:ok, persisted_membership} = Domain.get_device_group_membership(membership.id)
      assert persisted_membership.id == membership.id

      assert {:error, _error} = Domain.create_device_group(%{name: "WAREHOUSE SENSORS"})
      assert {:error, _error} = Domain.create_device_group(%{name: "   "})

      assert {:ok, restored} = Domain.update_device_group(archived, %{archived_at: nil})
      assert is_nil(restored.archived_at)
      assert Enum.map(Ash.load!(restored, :devices).devices, & &1.id) == [device.id]
      assert Enum.map(Ash.load!(device, :device_groups).device_groups, & &1.id) == [group.id]
      assert {:ok, persisted_membership} = Domain.get_device_group_membership(membership.id)
      assert persisted_membership.id == membership.id
    end

    test "normalizes renames and rejects blank or reserved names" do
      {:ok, group} = Domain.create_device_group(%{name: "Original"})
      {:ok, _active} = Domain.create_device_group(%{name: "Active"})
      {:ok, reserved} = Domain.create_device_group(%{name: "Reserved"})
      {:ok, _reserved} = Domain.update_device_group(reserved, %{archived_at: DateTime.utc_now()})

      assert {:ok, renamed} = Domain.update_device_group(group, %{name: "  Renamed Group  "})
      assert renamed.name == "Renamed Group"
      assert renamed.name_key == "renamed group"

      assert {:error, _error} = Domain.update_device_group(renamed, %{name: "   "})
      assert {:error, _error} = Domain.update_device_group(renamed, %{name: "ACTIVE"})
      assert {:error, _error} = Domain.update_device_group(renamed, %{name: "RESERVED"})
    end

    test "supports many-to-many memberships and rejects duplicate pairs" do
      device = device_fixture("11:22:33:44:55:66")
      {:ok, first_group} = Domain.create_device_group(%{name: "First"})
      {:ok, second_group} = Domain.create_device_group(%{name: "Second"})

      assert {:ok, _membership} =
               Domain.create_device_group_membership(%{
                 group_id: first_group.id,
                 device_id: device.id
               })

      assert {:ok, _membership} =
               Domain.create_device_group_membership(%{
                 group_id: second_group.id,
                 device_id: device.id
               })

      assert {:error, _error} =
               Domain.create_device_group_membership(%{
                 group_id: first_group.id,
                 device_id: device.id
               })

      first_group = Ash.load!(first_group, :devices)
      device = Ash.load!(device, :device_groups)

      assert Enum.map(first_group.devices, & &1.id) == [device.id]

      assert MapSet.new(Enum.map(device.device_groups, & &1.id)) ==
               MapSet.new([first_group.id, second_group.id])
    end

    test "permanent deletion requires an archived empty group" do
      device = device_fixture("22:33:44:55:66:77")
      {:ok, group} = Domain.create_device_group(%{name: "Delete safely"})

      assert {:error, _error} = Domain.destroy_device_group(group)

      {:ok, stale_archived} = Domain.update_device_group(group, %{archived_at: DateTime.utc_now()})
      {:ok, restored} = Domain.update_device_group(stale_archived, %{archived_at: nil})

      assert {:error, _error} = Domain.destroy_device_group(stale_archived)
      assert {:ok, active} = Domain.get_device_group(restored.id)
      assert is_nil(active.archived_at)

      {:ok, archived} = Domain.update_device_group(active, %{archived_at: DateTime.utc_now()})

      {:ok, membership} =
        Domain.create_device_group_membership(%{group_id: archived.id, device_id: device.id})

      assert {:error, _error} = Domain.destroy_device_group(archived)
      assert :ok = Domain.destroy_device_group_membership(membership)
      assert :ok = Domain.destroy_device_group(archived)
      assert {:error, %Ash.Error.Invalid{}} = Domain.get_device_group(archived.id)
    end

    test "deleting a device removes its memberships without deleting the group" do
      device = device_fixture("33:44:55:66:77:88")
      {:ok, group} = Domain.create_device_group(%{name: "Retained"})

      {:ok, membership} =
        Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})

      assert :ok = Domain.destroy_device(device)

      assert {:error, %Ash.Error.Invalid{}} =
               Domain.get_device_group_membership(membership.id)

      assert {:ok, retained} = Domain.get_device_group(group.id)
      assert retained.id == group.id
    end
  end

  defp device_fixture(mac_address) do
    {:ok, device} =
      Devices.create_device(%{mac_address: mac_address, product_name: "sensor"})

    device
  end
end
