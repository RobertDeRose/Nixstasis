alias Nixstasis.Domain
alias Nixstasis.Monitoring
alias Nixstasis.Reporting

IO.puts("Seeding sample data for schema-driven builder testing...")

now = DateTime.utc_now() |> DateTime.truncate(:second)

schema_v1 = %{
  "version" => "v1",
  "properties" => %{
    "temp" => %{"type" => "number"},
    "humidity" => %{"type" => "number"},
    "status" => %{"type" => "string"},
    "sensors" => %{
      "properties" => %{
        "pressure" => %{"type" => "number"}
      }
    }
  }
}

schema_v2 = %{
  "version" => "v2",
  "properties" => %{
    "temperature_c" => %{"type" => "number"},
    "humidity" => %{"type" => "number"},
    "battery" => %{"type" => "number"},
    "status" => %{"type" => "string"}
  }
}

schema_weather = %{
  "version" => "v1",
  "properties" => %{
    "wind_speed" => %{"type" => "number"},
    "rainfall" => %{"type" => "number"},
    "status" => %{"type" => "string"}
  }
}

upsert_device = fn attrs ->
  mac = attrs[:mac_address]

  case Domain.get_device_by_mac(mac) do
    {:ok, nil} ->
      Domain.create_device(attrs)

    {:ok, device} ->
      Domain.update_device(device, Map.delete(attrs, :mac_address))

    {:error, error} ->
      {:error, error}
  end
end

{:ok, d1} =
  upsert_device.(%{
    mac_address: "AA:BB:CC:00:00:11",
    product_name: "thermostat-v1",
    account_number: "10001",
    last_seen_at: now,
    schema: schema_v1
  })

{:ok, _d2} =
  upsert_device.(%{
    mac_address: "AA:BB:CC:00:00:12",
    product_name: "thermostat-v1",
    account_number: "10002",
    last_seen_at: now,
    schema: schema_v2
  })

{:ok, d3} =
  upsert_device.(%{
    mac_address: "AA:BB:CC:00:00:13",
    product_name: "weather-station",
    account_number: "10003",
    last_seen_at: now,
    schema: schema_weather
  })

IO.puts("Seeded/upserted devices: #{d1.mac_address}, AA:BB:CC:00:00:12, #{d3.mac_address}")

rule_exists? =
  Monitoring.list_rules_for_product("thermostat-v1")
  |> Enum.any?(fn r ->
    r.condition_field == "temp" and to_string(r.operator) == ">" and r.threshold_value == "72"
  end)

unless rule_exists? do
  {:ok, _rule} =
    Monitoring.create_rule(%{
      product_name: "thermostat-v1",
      condition_field: "temp",
      operator: :>,
      threshold_value: "72"
    })

  IO.puts("Created alert rule for thermostat-v1 temp threshold.")
end

report_exists? =
  Reporting.list_custom_reports()
  |> Enum.any?(&(&1.name == "Schema Seed Report"))

unless report_exists? do
  {:ok, _report} =
    Reporting.create_custom_report(%{
      "name" => "Schema Seed Report",
      "config" => %{
        "source" => "telemetry",
        "schema_id" => "thermostat-v1",
        "schema_version" => "v1",
        "fields" => [
          %{"path" => "temp", "alias" => "Temperature"},
          %{"path" => "humidity", "alias" => "Humidity"},
          %{"path" => "status", "alias" => "Status"}
        ],
        "filters" => [
          %{"field" => "status", "operator" => "=", "value" => "ok"}
        ]
      }
    })

  IO.puts("Created sample custom report.")
end

for {device, payload} <- [
      {d1, %{"temp" => 68, "humidity" => 48, "status" => "ok", "sensors" => %{"pressure" => 1009}}},
      {d1, %{"temp" => 74, "humidity" => 50, "status" => "warn", "sensors" => %{"pressure" => 1011}}},
      {d3, %{"wind_speed" => 11, "rainfall" => 0.2, "status" => "ok"}}
    ] do
  {:ok, _event} =
    Domain.create_telemetry_event(%{
      device_id: device.id,
      payload: payload,
      timestamp: now
    })
end

IO.puts("Inserted sample telemetry events.")
IO.puts("Seed complete.")
