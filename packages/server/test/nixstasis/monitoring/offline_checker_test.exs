defmodule Nixstasis.Monitoring.OfflineCheckerTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.OfflineChecker
  alias Nixstasis.Settings

  test "uses the stored offline window when checking devices" do
    assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => 20})

    {:ok, device} = Devices.register_device(%{mac_address: "44:44:44:44:44:44", product_name: "P1"})
    {:ok, device} = Devices.approve_device(device)

    {:ok, _device} =
      Devices.update_device(device, %{
        last_seen_at: DateTime.utc_now() |> DateTime.add(-15, :minute)
      })

    {:ok, checker} = GenServer.start_link(OfflineChecker, %{})

    send(checker, :check)
    :sys.get_state(checker)

    assert Repo.all(Alert) == []
  end
end
