defmodule Nixstasis.Monitoring.TelemetryTest do
  use Nixstasis.DataCase, async: true

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.TelemetryLimits

  setup do
    {:ok, device} = Devices.create_device(%{mac_address: "10:00:00:00:00:03"})
    %{device: device}
  end

  test "native map validation supports telemetry creates and updates", %{device: device} do
    assert {:ok, event} =
             Domain.create_telemetry_event(%{
               device_id: device.id,
               timestamp: DateTime.utc_now(),
               payload: %{"temperature" => 21}
             })

    assert {:ok, updated} =
             event
             |> Ash.Changeset.for_update(:update, %{payload: %{"temperature" => 22}})
             |> Ash.update(domain: Domain)

    assert updated.payload == %{"temperature" => 22}

    assert {:error, %Ash.Error.Invalid{}} =
             updated
             |> Ash.Changeset.for_update(:update, %{payload: "not a map"})
             |> Ash.update(domain: Domain)
  end

  test "rejects non-map telemetry before creating an event", %{device: device} do
    assert {:error, %Ash.Error.Invalid{}} =
             Domain.create_telemetry_event(%{
               device_id: device.id,
               timestamp: DateTime.utc_now(),
               payload: "not a map"
             })

    assert {:ok, []} = Domain.list_telemetry_events()
  end

  test "direct telemetry writes cannot bypass persistence limits", %{device: device} do
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

  test "telemetry updates validate persistence limits before writing", %{device: device} do
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
