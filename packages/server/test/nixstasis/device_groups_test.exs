defmodule Nixstasis.DeviceGroupsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Devices.GroupAuthorization
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

  describe "scoped group reads and metadata lifecycle" do
    test "scopes group visibility, visible counts, and membership lookup" do
      first = device_fixture("40:44:55:66:77:88")
      second = device_fixture("41:44:55:66:77:88")
      third = device_fixture("42:44:55:66:77:88")
      {:ok, shared} = Domain.create_device_group(%{name: "Shared"})
      {:ok, separate} = Domain.create_device_group(%{name: "Separate"})
      {:ok, empty} = Domain.create_device_group(%{name: "Empty"})
      {:ok, archived} = Domain.create_device_group(%{name: "Archived"})

      for {group, device} <- [{shared, first}, {shared, second}, {separate, third}, {archived, first}] do
        {:ok, _membership} =
          Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})
      end

      {:ok, archived} = Domain.update_device_group(archived, %{archived_at: DateTime.utc_now()})
      scoped = authorization([first.id, third.id])

      scoped_rows = Devices.list_device_groups(scoped)
      assert length(scoped_rows) == 2
      assert Enum.find(scoped_rows, &(&1.group.id == shared.id)).visible_device_count == 1
      assert Enum.find(scoped_rows, &(&1.group.id == separate.id)).visible_device_count == 1
      refute Enum.any?(scoped_rows, &(&1.group.id == empty.id))

      assert Devices.list_group_memberships(shared.id, scoped) == [first.id]
      assert Devices.list_device_groups(authorization([])) == []
      assert Devices.list_group_memberships(shared.id, authorization([])) == []

      unscoped_rows = Devices.list_device_groups(authorization(nil))
      assert Enum.find(unscoped_rows, &(&1.group.id == shared.id)).visible_device_count == 2
      assert Enum.find(unscoped_rows, &(&1.group.id == empty.id)).visible_device_count == 0
      refute Enum.any?(unscoped_rows, &(&1.group.id == archived.id))

      archived_rows = Devices.list_device_groups(authorization(nil), include_archived?: true)
      assert Enum.any?(archived_rows, &(&1.group.id == archived.id))

      unscoped_viewer = %{
        authorization(nil)
        | can_manage_devices?: false,
          can_manage_all_devices?: false
      }

      viewer_rows = Devices.list_device_groups(unscoped_viewer, include_archived?: true)
      refute Enum.any?(viewer_rows, &(&1.group.id in [empty.id, archived.id]))

      {:ok, _archived_shared} = Domain.update_device_group(shared, %{archived_at: DateTime.utc_now()})
      assert Devices.list_group_memberships(shared.id, scoped) == []
      assert Devices.list_devices(filter: %{group_id: shared.id}) == []
    end

    test "metadata lifecycle requires an unscoped manager with a trusted actor" do
      unscoped = authorization(nil)
      scoped = authorization([])
      viewer = %{scoped | can_manage_devices?: false}
      missing_actor = %{unscoped | actor_id: " "}

      assert {:error, :unauthorized} = Devices.create_device_group(%{name: "Denied"}, scoped)
      assert {:error, :unauthorized} = Devices.create_device_group(%{name: "Denied"}, viewer)
      assert {:error, :missing_actor} = Devices.create_device_group(%{name: "Denied"}, missing_actor)

      assert {:ok, group} =
               Devices.create_device_group(%{name: "  Lifecycle  ", description: "Initial"}, unscoped)

      assert {:ok, updated} =
               Devices.update_device_group(group.id, %{name: "Renamed", description: "Updated"}, unscoped)

      assert updated.name == "Renamed"
      assert updated.description == "Updated"
      assert {:ok, archived} = Devices.archive_device_group(group.id, unscoped)
      assert archived.archived_at
      assert {:ok, restored} = Devices.restore_device_group(group.id, unscoped)
      assert is_nil(restored.archived_at)
      assert {:error, :group_not_archived} = Devices.permanently_delete_device_group(group.id, unscoped)

      assert {:ok, archived} = Devices.archive_device_group(group.id, unscoped)
      assert :ok = Devices.permanently_delete_device_group(archived.id, unscoped)
      assert {:error, :group_not_found} = Devices.update_device_group(group.id, %{name: "Gone"}, unscoped)
    end

    test "metadata conflicts roll back without changing the target" do
      auth = authorization(nil)
      {:ok, first} = Devices.create_device_group(%{name: "First"}, auth)
      {:ok, _second} = Devices.create_device_group(%{name: "Second"}, auth)

      assert {:error, _error} = Devices.update_device_group(first.id, %{name: "SECOND"}, auth)
      assert {:ok, persisted} = Domain.get_device_group(first.id)
      assert persisted.name == "First"
    end
  end

  defp authorization(device_ids) do
    %GroupAuthorization{
      actor_id: "operator-1",
      can_manage_devices?: true,
      can_manage_all_devices?: is_nil(device_ids),
      authorized_device_ids: if(is_nil(device_ids), do: nil, else: MapSet.new(device_ids))
    }
  end

  defp device_fixture(mac_address) do
    {:ok, device} =
      Devices.create_device(%{mac_address: mac_address, product_name: "sensor"})

    device
  end
end
