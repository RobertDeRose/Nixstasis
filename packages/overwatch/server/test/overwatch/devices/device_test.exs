defmodule Nixstasis.Devices.DeviceTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices.Device

  describe "device validation" do
    test "validates required fields" do
      changeset = Device.changeset(%Device{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).mac_address
      assert "can't be blank" in errors_on(changeset).product_key
    end

    test "validates approval_status inclusion" do
      changeset =
        Device.changeset(%Device{}, %{
          mac_address: "AA:BB:CC",
          product_key: "key",
          approval_status: "invalid"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).approval_status
    end

    test "valid device" do
      changeset =
        Device.changeset(%Device{}, %{
          mac_address: "AA:BB:CC",
          product_key: "key",
          approval_status: "pending"
        })

      assert changeset.valid?
    end
  end
end
