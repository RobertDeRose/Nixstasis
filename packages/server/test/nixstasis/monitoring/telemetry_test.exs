defmodule Nixstasis.Monitoring.TelemetryTest do
  use Nixstasis.DataCase, async: true

  alias Nixstasis.Devices
  alias Nixstasis.Domain

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
end
