defmodule Nixstasis.Monitoring.AlertWorkerTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring
  alias Nixstasis.Monitoring.Alert

  describe "offline detection" do
    test "check_offline_devices/1 creates alerts for offline devices" do
      # Offline device (10 mins ago)
      {:ok, offline} =
        Devices.register_device(%{mac_address: "11:11:11:11:11:11", product_name: "P1"})

      {:ok, offline} = Devices.approve_device(offline)

      {:ok, offline} =
        Devices.update_device(offline, %{
          last_seen_at: DateTime.utc_now() |> DateTime.add(-600, :second)
        })

      # Online device (1 min ago)
      {:ok, online} =
        Devices.register_device(%{mac_address: "22:22:22:22:22:22", product_name: "P1"})

      {:ok, online} = Devices.approve_device(online)

      {:ok, _online} =
        Devices.update_device(online, %{
          last_seen_at: DateTime.utc_now() |> DateTime.add(-60, :second)
        })

      # Check with 5 min window
      Monitoring.check_offline_devices(window_minutes: 5)

      # Verify Alert
      assert [alert] = Repo.all(Alert)
      assert alert.device_id == offline.id
      assert alert.type == :offline
      assert alert.status == :active
    end

    test "check_offline_devices/1 does not duplicate active alerts" do
      {:ok, offline} =
        Devices.register_device(%{mac_address: "33:33:33:33:33:33", product_name: "P1"})

      {:ok, offline} = Devices.approve_device(offline)

      {:ok, _offline} =
        Devices.update_device(offline, %{
          last_seen_at: DateTime.utc_now() |> DateTime.add(-600, :second)
        })

      Monitoring.check_offline_devices(window_minutes: 5)
      Monitoring.check_offline_devices(window_minutes: 5)

      assert length(Repo.all(Alert)) == 1
    end
  end
end
