defmodule Nixstasis.Devices.DeviceTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  describe "device validation" do
    test "validates required fields" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} = Devices.create_device(%{})
      assert Enum.any?(errors, fn error -> Map.get(error, :field) == :mac_address end)
    end

    test "validates approval_status inclusion" do
      assert {:error, %Ash.Error.Invalid{errors: errors}} =
               Devices.create_device(%{
                 mac_address: "11:11:11:11:11:11",
                 product_name: "key",
                 approval_status: "invalid"
               })

      assert Enum.any?(errors, fn error -> Map.get(error, :field) == :approval_status end)
    end

    test "valid device" do
      assert {:ok, _device} =
               Devices.create_device(%{
                 mac_address: "11:11:11:11:11:11",
                 product_name: "key",
                 approval_status: :pending
               })
    end

    test "accepts new fields" do
      attrs = %{
        mac_address: "AA:BB:CC:DD:EE:FF",
        product_name: "key123",
        account_number: "12345",
        remote_access_requested: true
      }

      assert {:ok, device} = Devices.create_device(attrs)
      assert device.account_number == "12345"
      assert device.remote_access_requested == true
    end
  end
end
