defmodule Nixstasis.Reporting.QueryBuilderTest do
  use Nixstasis.DataCase, async: true
  alias Nixstasis.Reporting.QueryBuilder
  alias Nixstasis.Devices
  alias Nixstasis.Monitoring.Telemetry

  setup do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:01",
        "product_name" => "sensor-v1",
        "schema" => %{"type" => "object"}
      })

    # Manually insert telemetry to bypass context helpers if needed, or use Repo
    # Telemetry schema requires device_id, payload, timestamp
    t1 = %Telemetry{
      device_id: device.id,
      payload: %{"temp" => 25, "humidity" => 60},
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Repo.insert!(t1)

    t2 = %Telemetry{
      device_id: device.id,
      payload: %{"temp" => 30, "humidity" => 55},
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Repo.insert!(t2)

    %{device: device}
  end

  describe "build_query/1" do
    test "extracts fields from jsonb payload", %{device: device} do
      config = %{
        source: "telemetry",
        fields: [
          %{path: "temp", alias: "temperature"},
          %{path: "humidity", alias: "humidity"}
        ],
        filters: [
          %{field: "device_id", operator: "=", value: device.id}
        ]
      }

      query = QueryBuilder.build(config)
      results = Repo.all(query)

      # Expecting maps with string keys
      assert length(results) == 2
      first = List.first(results)
      assert Map.has_key?(first, "temperature")
      assert Map.has_key?(first, "humidity")
    end

    test "filters based on jsonb values", %{device: device} do
      config = %{
        source: "telemetry",
        fields: [%{path: "temp", alias: "temp"}],
        filters: [
          %{field: "device_id", operator: "=", value: device.id},
          %{path: "temp", operator: ">", value: 28}
        ]
      }

      query = QueryBuilder.build(config)
      results = Repo.all(query)

      assert length(results) == 1
      assert List.first(results)["temp"] == 30
    end
  end
end
