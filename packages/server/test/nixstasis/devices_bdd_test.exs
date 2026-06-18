defmodule Nixstasis.DevicesBDDTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  describe "User Story 2: Bulk Approval Workflow" do
    @valid_attrs %{mac_address: "AA:BB:CC:DD:EE:FF", product_name: "key"}

    def device_fixture(attrs) do
      {:ok, device} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Devices.create_device()

      device
    end

    test "Scenario 1: Filter awaiting approval" do
      # GIVEN multiple devices in "awaiting approval" state
      d1 =
        device_fixture(%{
          mac_address: "11:11:11:11:11:11",
          product_name: "k1",
          approval_status: :pending
        })

      d2 =
        device_fixture(%{
          mac_address: "22:22:22:22:22:22",
          product_name: "k2",
          approval_status: :pending
        })

      # AND a device in :approved state
      _d3 =
        device_fixture(%{
          mac_address: "33:33:33:33:33:33",
          product_name: "k3",
          approval_status: :approved
        })

      # WHEN the user filters for "awaiting approval" (pending)
      results = Devices.list_devices(filter: %{approval_status: :pending})

      # THEN only those devices are shown
      ids = Enum.map(results, & &1.id)
      assert d1.id in ids
      assert d2.id in ids
      assert length(ids) == 2
    end

    test "Scenario 2: Bulk Approve" do
      # GIVEN multiple selected pending devices
      d1 =
        device_fixture(%{
          mac_address: "11:11:11:11:11:11",
          product_name: "k1",
          approval_status: :pending
        })

      d2 =
        device_fixture(%{
          mac_address: "22:22:22:22:22:22",
          product_name: "k2",
          approval_status: :pending
        })

      # WHEN the user clicks "Approve" (calls approve_devices)
      Devices.approve_devices([d1.id, d2.id])

      # THEN all selected devices are authorized
      assert Devices.get_device!(d1.id).approval_status == :approved
      assert Devices.get_device!(d2.id).approval_status == :approved
    end

    test "bulk approve preserves tokens for devices that were already approved" do
      pending = device_fixture(%{mac_address: "44:44:44:44:44:44", product_name: "k4", approval_status: :pending})
      approved = device_fixture(%{mac_address: "55:55:55:55:55:55", product_name: "k5", approval_status: :approved})

      assert {:ok, approved, token} = Devices.issue_device_token(approved)

      assert :ok = Devices.authenticate_device(approved, token)
      assert %{status: :success} = Devices.approve_devices([pending.id, approved.id])

      assert Devices.get_device!(pending.id).approval_status == :approved
      assert :ok = approved.id |> Devices.get_device!() |> Devices.authenticate_device(token)
    end

    test "Scenario 3: Bulk Reject" do
      # GIVEN multiple selected pending devices
      d1 =
        device_fixture(%{
          mac_address: "11:11:11:11:11:11",
          product_name: "k1",
          approval_status: :pending
        })

      d2 =
        device_fixture(%{
          mac_address: "22:22:22:22:22:22",
          product_name: "k2",
          approval_status: :pending
        })

      # WHEN the user clicks "Reject" (calls reject_devices)
      Devices.reject_devices([d1.id, d2.id])

      # THEN all selected devices are rejected
      assert Devices.get_device!(d1.id).approval_status == :rejected
      assert Devices.get_device!(d2.id).approval_status == :rejected
    end
  end
end
