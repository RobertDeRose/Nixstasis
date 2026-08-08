defmodule Nixstasis.Monitoring.TelemetryRetentionTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring
  alias Nixstasis.Monitoring.Telemetry

  test "prunes telemetry outside the configured retention window" do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => unique_mac(),
        "product_name" => "retention-test-device"
      })

    _old_event =
      Repo.insert!(%Telemetry{
        device_id: device.id,
        payload: %{"status" => "old"},
        timestamp:
          DateTime.utc_now()
          |> DateTime.add(-31 * 86_400, :second)
          |> DateTime.truncate(:second)
      })

    _recent_event =
      Repo.insert!(%Telemetry{
        device_id: device.id,
        payload: %{"status" => "recent"},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    assert {:ok, %{pruned_events: 1, retention_days: 30}} =
             Monitoring.prune_telemetry_events(retention_days: 30)

    events = Repo.all(Telemetry)
    refute Enum.any?(events, &(&1.payload["status"] == "old"))
    assert Enum.any?(events, &(&1.payload["status"] == "recent"))
  end

  test "rejects a non-positive retention window" do
    assert {:error, :invalid_retention_days} =
             Monitoring.prune_telemetry_events(retention_days: 0)
  end

  defp unique_mac do
    suffix =
      System.unique_integer([:positive])
      |> rem(0xFFFFFF)
      |> Integer.to_string(16)
      |> String.pad_leading(6, "0")
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.join(":")

    "02:00:00:" <> suffix
  end
end
