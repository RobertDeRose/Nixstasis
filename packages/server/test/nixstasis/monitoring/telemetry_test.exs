defmodule Nixstasis.Monitoring.TelemetryTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.TelemetryLimits

  test "direct telemetry writes cannot bypass persistence limits" do
    {:ok, device} =
      Devices.register_device(%{mac_address: "12:34:56:78:9A:BC", product_name: "P1"})

    {:ok, device} = Devices.approve_device(device)
    limits = TelemetryLimits.limits()

    assert {:error, error} =
             Domain.create_telemetry_event(%{
               device_id: device.id,
               payload: %{"blob" => String.duplicate("x", limits.max_string_bytes + 1)},
               timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
             })

    assert Exception.message(error) =~ "telemetry string exceeds maximum size"
    assert Domain.list_telemetry_events!() == []
  end

  test "telemetry updates validate persistence limits before writing" do
    {:ok, device} =
      Devices.register_device(%{mac_address: "12:34:56:78:9A:BD", product_name: "P1"})

    {:ok, device} = Devices.approve_device(device)

    {:ok, telemetry} =
      Domain.create_telemetry_event(%{
        device_id: device.id,
        payload: %{"status" => "pending"},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    assert {:ok, updated} =
             telemetry
             |> Ash.Changeset.for_update(:update, %{payload: %{"status" => "ok"}})
             |> Ash.update()

    assert updated.payload == %{"status" => "ok"}

    assert {:error, error} =
             updated
             |> Ash.Changeset.for_update(:update, %{
               payload: %{"blob" => String.duplicate("x", TelemetryLimits.limits().max_string_bytes + 1)}
             })
             |> Ash.update()

    assert Exception.message(error) =~ "telemetry string exceeds maximum size"
    assert [%{payload: %{"status" => "ok"}}] = Domain.list_telemetry_events!()
  end
end
