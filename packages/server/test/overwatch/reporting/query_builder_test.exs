defmodule Nixstasis.Reporting.QueryBuilderTest do
  use Nixstasis.DataCase, async: true
  alias Nixstasis.Reporting.QueryBuilder
  alias Nixstasis.E2E.Run
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

    run =
      Repo.insert!(%Run{
        suite_id: "full",
        journey_ids: ["auth", "logout"],
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        status: "passed",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
        run_metadata: %{}
      })

    %{device: device, run: run}
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

    test "supports nested json path extraction for telemetry", %{device: device} do
      nested = %{
        device_id: device.id,
        payload: %{
          "scripts" => %{
            "mem_linux" => %{
              "data" => %{
                "output" => %{"memory_used_percent" => 47.2}
              }
            }
          }
        },
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      Repo.insert!(struct(Telemetry, nested))

      config = %{
        source: "telemetry",
        fields: [
          %{path: "scripts.mem_linux.data.output.memory_used_percent", alias: "mem_pct"}
        ],
        filters: [
          %{field: "device_id", operator: "=", value: device.id},
          %{path: "scripts.mem_linux.data.output.memory_used_percent", operator: ">", value: 40}
        ]
      }

      query = QueryBuilder.build(config)
      results = Repo.all(query)

      assert Enum.any?(results, fn row -> row["mem_pct"] == "47.2" or row["mem_pct"] == 47.2 end)
    end

    test "supports e2e source with explicit fields", %{run: run} do
      config = %{
        source: "e2e",
        fields: [
          %{path: "id", alias: "run_id"},
          %{path: "status", alias: "status"}
        ],
        filters: [
          %{field: "id", operator: "=", value: run.id}
        ]
      }

      query = QueryBuilder.build(config)
      results = Repo.all(query)

      assert length(results) == 1
      first = List.first(results)
      assert first["run_id"] == run.id
      assert first["status"] == "passed"
    end

    test "ignores unknown schema keys in filters for telemetry source", %{device: device} do
      config = %{
        source: "telemetry",
        fields: [%{path: "temp", alias: "temp"}],
        filters: [
          %{field: "device_id", operator: "=", value: device.id},
          %{field: "unknown_field", operator: "=", value: "x"}
        ]
      }

      query = QueryBuilder.build(config)
      results = Repo.all(query)

      assert length(results) == 2
    end

    test "provides default fields for e2e source when none are configured" do
      fields = QueryBuilder.fields_for_report(%{source: "e2e", fields: []})
      assert fields != []
      assert Enum.any?(fields, fn field -> field["path"] == "status" end)
    end
  end
end
