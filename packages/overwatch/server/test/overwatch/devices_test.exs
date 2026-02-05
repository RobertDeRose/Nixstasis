defmodule Nixstasis.DevicesTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  describe "devices" do
    @valid_attrs %{mac_address: "AA:BB:CC:DD:EE:FF", product_key: "key"}

    def device_fixture(attrs \\ %{}) do
      {:ok, device} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Devices.create_device()

      device
    end

    test "list_devices/0 returns all devices" do
      device = device_fixture()
      assert Devices.list_devices() == [device]
    end

    test "list_devices/1 sorts by ipv4_address" do
      d1 = device_fixture(%{mac_address: "01", product_key: "k1", ipv4_address: "10.0.0.2"})
      d2 = device_fixture(%{mac_address: "02", product_key: "k2", ipv4_address: "10.0.0.1"})

      assert [d2_res, d1_res] = Devices.list_devices(sort_by: :ipv4_address, sort_order: :asc)
      assert d2_res.id == d2.id
      assert d1_res.id == d1.id
    end

    test "list_devices/1 filters by approval_status" do
      pending =
        device_fixture(%{mac_address: "01", product_key: "k1", approval_status: "pending"})

      approved =
        device_fixture(%{mac_address: "02", product_key: "k2", approval_status: "approved"})

      assert [res] = Devices.list_devices(filter: %{status: "pending"})
      assert res.id == pending.id

      assert [res] = Devices.list_devices(filter: %{status: "approved"})
      assert res.id == approved.id
    end

    test "list_devices/1 searches by mac_address" do
      match = device_fixture(%{mac_address: "11:22:33:44:55:66", product_key: "k1"})
      _miss = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:FF", product_key: "k2"})

      assert [res] = Devices.list_devices(search: "11:22")
      assert res.id == match.id
    end

    test "approve_devices/1 approves multiple devices" do
      d1 = device_fixture(%{mac_address: "01", product_key: "k1", approval_status: "pending"})
      d2 = device_fixture(%{mac_address: "02", product_key: "k2", approval_status: "pending"})

      assert {2, nil} = Devices.approve_devices([d1.id, d2.id])

      assert Devices.get_device!(d1.id).approval_status == "approved"
      assert Devices.get_device!(d2.id).approval_status == "approved"
    end

    test "reject_devices/1 rejects multiple devices" do
      d1 = device_fixture(%{mac_address: "01", product_key: "k1", approval_status: "pending"})
      d2 = device_fixture(%{mac_address: "02", product_key: "k2", approval_status: "pending"})

      assert {2, nil} = Devices.reject_devices([d1.id, d2.id])

      assert Devices.get_device!(d1.id).approval_status == "rejected"
      assert Devices.get_device!(d2.id).approval_status == "rejected"
    end

    test "set_remote_access/2 toggles flag" do
      device = device_fixture()
      assert {:ok, updated} = Devices.set_remote_access(device, true)
      assert updated.remote_access_requested == true

      assert {:ok, updated} = Devices.set_remote_access(updated, false)
      assert updated.remote_access_requested == false
    end
  end
end
