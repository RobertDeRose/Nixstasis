#!/usr/bin/env bash
#MISE description="Seed deterministic schema-builder data into the Compose dev database"
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../../../.." && pwd)
cd "$ROOT_DIR"

rpc_code=$(cat <<'ELIXIR'
now = DateTime.utc_now() |> DateTime.truncate(:second)
product = "schema-builder-demo"

# These are database-only fixtures: no client container owns their MAC
# addresses, so they must remain offline and must never auto-open SSH.
# Add future deterministic devices and schema versions to this list. Keep MAC
# addresses and account numbers stable so rerunning the task remains idempotent.
schemas = [
  {
    "AA:BB:CC:DD:EE:71",
    "71001",
    %{
      "product" => product,
      "version" => "v1",
      "type" => "object",
      "properties" => %{
        "temperature" => %{"type" => "number"},
        "humidity" => %{"type" => "number"},
        "status" => %{"type" => "string"}
      }
    }
  },
  {
    "AA:BB:CC:DD:EE:72",
    "71002",
    %{
      "product" => product,
      "version" => "v2",
      "type" => "object",
      "properties" => %{
        "temperature_c" => %{"type" => "number"},
        "battery" => %{"type" => "number"},
        "status" => %{"type" => "string"}
      }
    }
  }
]

upserted_devices =
  Enum.map(schemas, fn {mac_address, account_number, schema} ->
    attrs = %{
      mac_address: mac_address,
      account_number: account_number,
      product_name: product,
      approval_status: :pending,
      last_seen_at: nil,
      schema: schema,
      metadata: %{"deploy_dev_seed" => "schema-builder"}
    }

    existing =
      Nixstasis.Devices.list_devices()
      |> Enum.find(&(&1.mac_address == mac_address))

    case existing do
      nil ->
        {:ok, device} = Nixstasis.Devices.create_device(attrs)
        device

      device ->
        {:ok, device} =
          Nixstasis.Devices.update_device(device, %{
            account_number: account_number,
            product_name: product,
            last_seen_at: nil,
            schema: schema,
            metadata: Map.merge(device.metadata || %{}, attrs.metadata)
          })

        device
    end
  end)

# Keep the example alert and report available for inspecting saved output. The
# names are stable and checked before creation, so reruns do not duplicate them.
rule_name = "Schema Builder Demo Alert"

unless Enum.any?(Nixstasis.Monitoring.list_rules_for_product(product), &(&1.name == rule_name)) do
  {:ok, _rule} =
    Nixstasis.Monitoring.create_rule(%{
      name: rule_name,
      product_name: product,
      condition_field: "temperature",
      operator: :>,
      threshold_value: "25"
    })
end

report_name = "Schema Builder Demo Report"

unless Enum.any?(Nixstasis.Reporting.list_custom_reports(), &(&1.name == report_name)) do
  {:ok, _report} =
    Nixstasis.Reporting.create_custom_report(%{
      "name" => report_name,
      "config" => %{
        "source" => "telemetry",
        "schema_id" => product,
        "schema_version" => "v1",
        "fields" => [
          %{"path" => "temperature", "alias" => "Temperature"},
          %{"path" => "humidity", "alias" => "Humidity"},
          %{"path" => "status", "alias" => "Status"}
        ],
        "filters" => []
      }
    })
end

# Add data once per sample. Each sample has a stable marker so a partial
# fixture batch is repaired on a later invocation instead of being skipped.
# The second lookup preserves idempotency for events written by the original
# batch-wide marker implementation.
seed_marker = "schema-builder-v1"
v1 = Enum.find(upserted_devices, &(&1.schema["version"] == "v1"))
v2 = Enum.find(upserted_devices, &(&1.schema["version"] == "v2"))

samples = [
  {v1, %{"temperature" => 19.5, "humidity" => 42.0, "status" => "ok"}},
  {v1, %{"temperature" => 27.2, "humidity" => 58.0, "status" => "warm"}},
  {v2, %{"temperature_c" => 21.0, "battery" => 91.0, "status" => "ok"}},
  {v2, %{"temperature_c" => 24.5, "battery" => 76.0, "status" => "warn"}}
]

inserted_count =
  Enum.reduce(Enum.with_index(samples, 1), 0, fn {{device, payload}, index}, count ->
    sample_marker = "#{seed_marker}-#{index}"

    sample_payload = Map.put(payload, "deploy_dev_seed_sample", sample_marker)

    exists? =
      Nixstasis.Monitoring.telemetry_seed_sample_exists?(seed_marker, device.id, sample_payload) or
        Nixstasis.Monitoring.telemetry_seed_sample_exists?(seed_marker, device.id, payload)

    if exists? do
      count
    else
      {:ok, _event} =
        Nixstasis.Domain.create_telemetry_event(%{
          device_id: device.id,
          timestamp: DateTime.add(now, -(index - 1) * 60, :second),
          payload: Map.put(sample_payload, "deploy_dev_seed", seed_marker)
        })

      count + 1
    end
  end)

if inserted_count == 0 do
  IO.puts("#{seed_marker} telemetry already exists; no duplicate events inserted.")
else
  IO.puts("Inserted #{inserted_count} #{seed_marker} telemetry events.")
end

IO.puts("Seeded #{product} schema versions v1 and v2 as offline fixtures.")
IO.puts("Seeded alert: #{rule_name}")
IO.puts("Seeded report: #{report_name}")
ELIXIR
)

mise run deploy:dev -- exec -T nixstasis /app/bin/nixstasis rpc "$rpc_code"
