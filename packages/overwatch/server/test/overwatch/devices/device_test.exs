defmodule Nixstasis.Devices.DeviceTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices.Device

  describe "device validation" do
    test "validates required fields" do
      changeset = Device.changeset(%Device{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).mac_address
    end

    test "validates approval_status inclusion" do
      changeset =
        Device.changeset(%Device{}, %{
          mac_address: "11:11:11:11:11:11",
          product_name: "key",
          approval_status: "invalid"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).approval_status
    end

    test "valid device" do
      changeset =
        Device.changeset(%Device{}, %{
          mac_address: "11:11:11:11:11:11",
          product_name: "key",
          approval_status: "pending"
        })

      assert changeset.valid?
    end

    test "accepts new fields" do
      attrs = %{
        mac_address: "AA:BB:CC:DD:EE:FF",
        product_name: "key123",
        ipv4_address: "192.168.1.1",
        account_number: "12345",
        remote_access_requested: true
      }

      changeset = Device.changeset(%Device{}, attrs)
      assert changeset.valid?
      assert get_field(changeset, :ipv4_address) == "192.168.1.1"
      assert get_field(changeset, :account_number) == "12345"
      assert get_field(changeset, :remote_access_requested) == true
    end
  end
end
