defmodule Nixstasis.Monitoring do
  @moduledoc """
  The Monitoring context.
  """

  require Ash.Query

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.AlertRule
  alias Nixstasis.Monitoring.RuleEvaluator

  def heartbeat(%Device{} = device, payload \\ %{}) do
    telemetry_payload = normalize_telemetry_payload(payload)

    with {:ok, device} <- Devices.update_last_seen(device),
         {:ok, _event} <- persist_telemetry_event(device, telemetry_payload) do
      # Evaluate telemetry against rules
      evaluate_telemetry(device, telemetry_payload)

      # Fetch pending commands
      commands = Devices.pop_pending_commands(device)

      {:ok, device, commands}
    end
  end

  def check_offline_devices(opts \\ []) do
    window = Keyword.get(opts, :window_minutes, 10)
    cutoff = DateTime.utc_now() |> DateTime.add(-window * 60, :second)

    device_ids =
      Device
      |> Ash.Query.filter(approval_status == :approved)
      |> Ash.Query.filter(last_seen_at < ^cutoff)
      |> Ash.Query.filter(not exists(alerts, type == :offline and status == :active))
      |> Ash.read!(domain: Domain)
      |> Enum.map(& &1.id)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(device_ids, fn id ->
        %{
          device_id: id,
          type: :offline,
          status: :active,
          message: "Device hasn't reported in #{window} minutes",
          triggered_at: now
        }
      end)

    if entries != [] do
      Ash.bulk_create(entries, Alert, :create, domain: Domain)
    else
      %Ash.BulkResult{status: :success, errors: []}
    end
  end

  def evaluate_telemetry(%Device{} = device, payload) do
    rules = list_rules_for_product(device.product_name)

    for rule <- rules do
      if RuleEvaluator.evaluate(payload, rule) do
        create_rule_alert(device, rule)
      end
    end
  end

  def list_rules do
    Domain.list_rules!()
  end

  def get_rule!(id), do: Domain.get_rule!(id)

  def create_rule(attrs \\ %{}) do
    Domain.create_rule(attrs)
  end

  def update_rule(rule, attrs \\ %{}) do
    Domain.update_rule(rule, attrs)
  end

  def delete_rule(%AlertRule{} = rule) do
    Domain.destroy_rule(rule)
  end

  def list_rules_for_product(product_name) do
    AlertRule
    |> Ash.Query.filter(product_name == ^product_name)
    |> Ash.read!(domain: Domain)
  end

  defp create_rule_alert(device, rule) do
    exists? =
      Alert
      |> Ash.Query.filter(device_id == ^device.id and rule_id == ^rule.id and status == :active)
      |> Ash.exists?(domain: Domain)

    unless exists? do
      Domain.create_alert(%{
        device_id: device.id,
        rule_id: rule.id,
        type: :threshold,
        status: :active,
        message: "Rule Breach: #{rule.condition_field} #{rule.operator} #{rule.threshold_value}",
        triggered_at: DateTime.utc_now()
      })
    end
  end

  defp persist_telemetry_event(%Device{} = device, payload) do
    Domain.create_telemetry_event(%{
      device_id: device.id,
      payload: payload,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp normalize_telemetry_payload(payload) when is_map(payload) do
    sanitized =
      payload
      |> Map.drop(["device_id", :device_id])

    case map_get(sanitized, "telemetry") do
      telemetry when is_map(telemetry) ->
        case map_get(sanitized, "connection_status") do
          connection_status when is_map(connection_status) ->
            Map.put_new(telemetry, "connection_status", connection_status)

          _ ->
            telemetry
        end

      _ ->
        sanitized
    end
  end

  defp normalize_telemetry_payload(_payload), do: %{}

  defp map_get(map, "telemetry") when is_map(map), do: Map.get(map, "telemetry") || Map.get(map, :telemetry)

  defp map_get(map, "connection_status") when is_map(map),
    do: Map.get(map, "connection_status") || Map.get(map, :connection_status)
end
