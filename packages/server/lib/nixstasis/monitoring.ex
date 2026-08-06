defmodule Nixstasis.Monitoring do
  @moduledoc """
  The Monitoring context.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  require Logger
  require Ash.Query

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.FrpsToken
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.AlertRule
  alias Nixstasis.Monitoring.RuleEvaluator
  alias Nixstasis.Notifications.Email
  alias Nixstasis.Repo
  alias Nixstasis.Notifications.Webhook
  alias Nixstasis.Settings

  def heartbeat(%Device{} = device, payload \\ %{}) do
    telemetry_payload = normalize_telemetry_payload(payload)

    with {:ok, device} <- Devices.update_last_seen(device),
         {:ok, _event} <- persist_telemetry_event(device, telemetry_payload),
         {:ok, _inventory} <- persist_command_inventory(device, payload) do
      resolve_offline_alerts(device)

      # Evaluate telemetry against rules
      evaluate_telemetry(device, telemetry_payload)

      # Fetch pending commands
      commands = Devices.pop_pending_commands(device)

      {:ok, device, commands}
    end
  end

  @doc """
  Builds the device-runtime heartbeat response shared by generated and legacy transports.
  """
  def heartbeat_response_data(%Device{} = device, commands) do
    %{
      commands:
        for(
          cmd <- commands,
          do: heartbeat_command_data(cmd)
        )
    }
    |> maybe_put_remote_access_token(FrpsToken.for_heartbeat(device))
    |> maybe_put_command_inventory_probe()
  end

  defp maybe_put_remote_access_token(data, nil), do: data
  defp maybe_put_remote_access_token(data, token), do: Map.put(data, :remote_access_token, token)

  defp maybe_put_command_inventory_probe(data) do
    case Domain.command_inventory_probe_manifest() do
      {:ok, manifest} -> Map.put(data, :command_inventory_probe, manifest)
      _ -> data
    end
  end

  defp heartbeat_command_data(cmd) do
    payload = cmd.command_payload || %{}
    payload_ref = payload["payload_ref"] || payload[:payload_ref]
    inline_payload = normalize_inline_payload(payload)

    %{
      command_id: cmd.id,
      type: payload["type"] || payload[:type] || "unknown",
      args: payload["args"] || payload[:args] || [],
      payload: inline_payload,
      public_key: payload["public_key"] || payload[:public_key],
      payload_ref: payload_ref,
      queued_at: cmd.queued_at
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp normalize_inline_payload(payload) do
    if deferred_payload?(payload) do
      nil
    else
      payload
      |> nested_payload()
      |> case do
        %{} = nested -> nested
        _ -> fallback_inline_payload(payload)
      end
    end
  end

  defp nested_payload(payload) do
    payload["payload"] || payload[:payload]
  end

  defp deferred_payload?(payload) do
    (payload["defer_payload"] || payload[:defer_payload]) == true and
      not is_nil(payload["payload_ref"] || payload[:payload_ref])
  end

  defp fallback_inline_payload(payload) do
    if has_transport_shape?(payload) do
      transport_payload(payload)
    else
      payload
    end
  end

  defp has_transport_shape?(payload) do
    not is_nil(payload["content_type"] || payload[:content_type]) or
      not is_nil(payload["name"] || payload[:name]) or
      not is_nil(payload["data"] || payload[:data])
  end

  defp transport_payload(payload) do
    %{
      "content_type" => payload["content_type"] || payload[:content_type],
      "name" => payload["name"] || payload[:name],
      "data" => payload["data"] || payload[:data]
    }
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
      result = Ash.bulk_create(entries, Alert, :create, domain: Domain, return_records?: true)

      result.records
      |> List.wrap()
      |> Enum.each(&handle_alert_created/1)

      result
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

  @doc "Returns whether an alert rule name is already used, ignoring case."
  def alert_rule_name_taken?(name, except_id \\ nil)

  def alert_rule_name_taken?(name, except_id) when is_binary(name) do
    if String.trim(name) == "" do
      false
    else
      query =
        from(rule in "alert_rules",
          where: fragment("lower(?) = lower(?)", rule.name, ^name),
          select: rule.id,
          limit: 1
        )

      query =
        if is_nil(except_id) do
          query
        else
          where(query, [rule], rule.id != ^except_id)
        end

      not is_nil(Repo.one(query))
    end
  end

  def alert_rule_name_taken?(_name, _except_id), do: false

  def list_rules_for_product(product_name) do
    AlertRule
    |> Ash.Query.filter(product_name == ^product_name)
    |> Ash.read!(domain: Domain)
  end

  @doc "Checks for one deterministic telemetry seed sample without loading telemetry rows."
  def telemetry_seed_sample_exists?(seed_marker, device_id, payload)
      when is_binary(seed_marker) and is_binary(device_id) and is_map(payload) do
    expected_payload = Map.put(payload, "deploy_dev_seed", seed_marker)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT 1
        FROM telemetry_events
        WHERE device_id = $1::uuid
          AND payload @> $2::jsonb
        LIMIT 1
        """,
        [Ecto.UUID.dump!(device_id), expected_payload]
      )

    rows != []
  end

  def telemetry_seed_sample_exists?(_seed_marker, _device_id, _payload), do: false

  defp create_rule_alert(device, rule) do
    exists? =
      Alert
      |> Ash.Query.filter(device_id == ^device.id and rule_id == ^rule.id and status == :active)
      |> Ash.exists?(domain: Domain)

    unless exists? do
      case Domain.create_alert(%{
             device_id: device.id,
             rule_id: rule.id,
             type: :threshold,
             status: :active,
             message: "Rule Breach: #{rule.condition_field} #{rule.operator} #{rule.threshold_value}",
             triggered_at: DateTime.utc_now()
           }) do
        {:ok, alert} -> handle_alert_created(alert)
        result -> result
      end
    end
  end

  defp resolve_offline_alerts(%Device{} = device) do
    Alert
    |> Ash.Query.filter(device_id == ^device.id and type == :offline and status == :active)
    |> Ash.read!(domain: Domain)
    |> Enum.each(fn alert ->
      case Domain.update_alert(alert, %{status: :resolved, message: "Device heartbeat resumed"}) do
        {:ok, _resolved_alert} -> :ok
        _ -> :ok
      end
    end)
  end

  defp persist_telemetry_event(%Device{} = device, payload) do
    Domain.create_telemetry_event(%{
      device_id: device.id,
      payload: payload,
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp persist_command_inventory(%Device{} = device, payload) when is_map(payload) do
    case map_get(payload, "command_inventory") do
      inventory when is_map(inventory) ->
        attrs =
          inventory
          |> Map.take([
            "schema_version",
            "probe_catalog_version",
            "observed_at",
            "architecture",
            "os_release",
            "os_family",
            "package_manager",
            "packages",
            "commands"
          ])
          |> Map.put("device_id", device.id)

        case Domain.create_device_command_inventory_snapshot(attrs) do
          {:ok, snapshot} ->
            {:ok, snapshot}

          {:error, reason} ->
            Logger.warning("Ignoring invalid command inventory for #{device.id}: #{inspect(reason)}")
            {:ok, :invalid_inventory}
        end

      _ ->
        {:ok, :none}
    end
  end

  defp persist_command_inventory(%Device{}, _payload), do: {:ok, :none}

  defp normalize_telemetry_payload(payload) when is_map(payload) do
    sanitized =
      payload
      |> Map.drop(["device_id", :device_id, "command_inventory", :command_inventory])

    case map_get(sanitized, "telemetry") do
      telemetry when is_map(telemetry) ->
        telemetry = Map.drop(telemetry, ["command_inventory", :command_inventory])

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

  defp map_get(map, "command_inventory") when is_map(map),
    do: Map.get(map, "command_inventory") || Map.get(map, :command_inventory)

  defp handle_alert_created(%Alert{} = alert) do
    broadcast_alert_created(alert)
    notify_alert_created(alert)
    {:ok, alert}
  end

  defp notify_alert_created(%Alert{} = alert) do
    settings = Settings.get_notifications_config()
    email = normalize_notification_target(Map.get(settings, "email"))
    webhook_url = normalize_notification_target(Map.get(settings, "webhook_url"))

    notify_alert_target(:email, email, alert, fn -> email_notifier().send_alert_email(email, alert) end)

    notify_alert_target(:webhook, webhook_url, alert, fn ->
      webhook_notifier().send_alert_webhook(webhook_url, alert)
    end)
  end

  defp notify_alert_target(_type, nil, _alert, _callback), do: :ok

  defp notify_alert_target(type, _target, %Alert{} = alert, callback) when is_function(callback, 0) do
    Task.start(fn -> deliver_alert_notification(type, alert, callback) end)
    :ok
  end

  defp deliver_alert_notification(type, %Alert{} = alert, callback) when is_function(callback, 0) do
    case callback.() do
      {:ok, _result} -> :ok
      :ok -> :ok
      {:error, reason} -> log_notification_failure(type, alert, reason)
      other -> log_notification_failure(type, alert, other)
    end
  rescue
    exception -> log_notification_failure(type, alert, Exception.message(exception))
  catch
    kind, reason -> log_notification_failure(type, alert, {kind, reason})
  end

  defp log_notification_failure(type, %Alert{} = alert, reason) do
    Logger.warning("alert #{type} notification failed for #{alert.id}: #{inspect(reason)}")

    :ok
  end

  defp normalize_notification_target(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_notification_target(_value), do: nil

  defp email_notifier do
    notifier_module(:email_notifier, Email)
  end

  defp webhook_notifier do
    notifier_module(:webhook_notifier, Webhook)
  end

  defp notifier_module(config_key, default) do
    case Application.get_env(:nixstasis, config_key, default) do
      {module, _opts} -> module
      module -> module
    end
  end

  defp broadcast_alert_created(%Alert{} = alert) do
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, "alerts", {:alert_created, alert})
  end
end
