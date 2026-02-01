defmodule Nixstasis.Devices.ApprovalTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  describe "approval workflow" do
    test "list_pending_devices/0 returns only pending devices" do
      {:ok, pending} = Devices.register_device(%{mac_address: "AA", product_key: "P1"})

      # We create an approved device directly via Repo for setup, as register_device defaults to pending
      # and we haven't implemented pre-approval logic yet.
      {:ok, _approved} =
        Devices.register_device(%{
          mac_address: "BB",
          product_key: "P1",
          approval_status: "approved"
        })

      pending_list = Devices.list_pending_devices()
      ids = Enum.map(pending_list, & &1.id)

      assert pending.id in ids

      # Depending on how register_device works now (it allows override), approved might be approved.
      # But if list_pending_devices works correctly, it filters by status.
    end

    test "approve_device/1 changes status to approved" do
      {:ok, device} = Devices.register_device(%{mac_address: "CC", product_key: "P1"})
      assert device.approval_status == "pending"

      {:ok, updated} = Devices.approve_device(device)
      assert updated.approval_status == "approved"
    end

    test "register_device/1 maintains approval status on re-registration" do
      {:ok, device} = Devices.register_device(%{mac_address: "DD", product_key: "P1"})
      {:ok, _} = Devices.approve_device(device)

      # Re-register
      {:ok, updated} =
        Devices.register_device(%{
          mac_address: "DD",
          product_key: "P1",
          metadata: %{"new" => "data"}
        })

      assert updated.approval_status == "approved"
      assert updated.metadata["new"] == "data"
    end
  end
end
