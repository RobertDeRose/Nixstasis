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
    {:ok, device} ->
      Domain.update_device(device, Map.delete(attrs, :mac_address))

    {:error, _error} ->
      Domain.create_device(attrs)
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

IO.puts("Seeding command catalog diagnostics entries...")

for attrs <- [
      %{slug: "diagnostics", display_name: "Diagnostics", description: "Read-only diagnostic commands"},
      %{slug: "storage", display_name: "Storage", description: "Filesystem and storage inspection commands"}
    ] do
  case Domain.create_command_catalog_category(attrs) do
    {:ok, _category} -> :ok
    {:error, _error} -> :ok
  end
end

catalog_commands = [
  %{
    name: "df",
    display_name: "Disk free",
    category_slugs: ["storage", "diagnostics"],
    package_name: "coreutils",
    command_path: "/usr/bin/df"
  },
  %{
    name: "uname",
    display_name: "Kernel identity",
    category_slugs: ["diagnostics"],
    package_name: "coreutils",
    command_path: "/usr/bin/uname"
  },
  %{
    name: "journalctl",
    display_name: "Systemd journal",
    category_slugs: ["diagnostics"],
    package_name: "systemd",
    command_path: "/usr/bin/journalctl"
  }
]

for command_attrs <- catalog_commands do
  {:ok, command} =
    case Domain.create_command_catalog_command(%{
           name: command_attrs.name,
           display_name: command_attrs.display_name,
           category_slugs: command_attrs.category_slugs,
           description: "Curated #{command_attrs.display_name} command",
           risk_notes: "Read-only diagnostic use through Stary exec_cmd policies.",
           install_guidance: "Install the mapped package for the target OS before assignment."
         }) do
      {:ok, command} ->
        {:ok, command}

      {:error, _error} ->
        Domain.list_command_catalog_commands()
        |> then(fn {:ok, commands} -> {:ok, Enum.find(commands, &(&1.name == command_attrs.name))} end)
    end

  for {os_family, package_manager} <- [{"debian", "apt"}, {"fedora", "dnf"}, {"nixos", "nix"}] do
    case Domain.create_command_catalog_mapping(%{
           catalog_command_id: command.id,
           os_family: os_family,
           package_manager: package_manager,
           package_name: command_attrs.package_name,
           command_path: command_attrs.command_path,
           install_hint: "Install #{command_attrs.package_name} with #{package_manager}."
         }) do
      {:ok, _mapping} -> :ok
      {:error, _error} -> :ok
    end
  end
end

IO.puts("Seeded command catalog diagnostics entries.")
IO.puts("Seed complete.")
