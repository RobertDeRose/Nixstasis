defmodule Nixstasis.Monitoring do
  @moduledoc """
  The Monitoring context.
  """

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Monitoring.Alert
  import Ecto.Query
  alias Nixstasis.Repo
  alias Nixstasis.Monitoring.AlertRule
  alias Nixstasis.Monitoring.RuleEvaluator

  def heartbeat(%Device{} = device, payload \\ %{}) do
    # Update last_seen_at
    {:ok, device} = Devices.update_last_seen(device)

    # Evaluate telemetry against rules
    evaluate_telemetry(device, payload)

    # Fetch pending commands
    commands = Devices.pop_pending_commands(device)

    {:ok, device, commands}
  end

  def check_offline_devices(opts \\ []) do
    window = Keyword.get(opts, :window_minutes, 10)
    cutoff = DateTime.utc_now() |> DateTime.add(-window * 60, :second)

    # Find devices that are offline and DON'T have an active offline alert
    query =
      from(d in Device,
        where: d.last_seen_at < ^cutoff,
        where: d.approval_status == "approved",
        left_join: a in Alert,
        on: a.device_id == d.id and a.type == "offline" and a.status == "active",
        where: is_nil(a.id),
        select: d.id
      )

    device_ids = Repo.all(query)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entries =
      Enum.map(device_ids, fn id ->
        %{
          id: Ecto.UUID.generate(),
          device_id: id,
          type: "offline",
          status: "active",
          message: "Device hasn't reported in #{window} minutes",
          triggered_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [] do
      Repo.insert_all(Alert, entries)
    else
      {0, nil}
    end
  end

  def evaluate_telemetry(%Device{} = device, payload) do
    rules = list_rules_for_product(device.product_key)

    for rule <- rules do
      if RuleEvaluator.evaluate(payload, rule) do
        create_rule_alert(device, rule)
      end
    end
  end

  def list_rules do
    Repo.all(AlertRule)
  end

  def get_rule!(id), do: Repo.get!(AlertRule, id)

  def create_rule(attrs \\ %{}) do
    %AlertRule{}
    |> AlertRule.changeset(attrs)
    |> Repo.insert()
  end

  def delete_rule(%AlertRule{} = rule) do
    Repo.delete(rule)
  end

  def list_rules_for_product(product_key) do
    Repo.all(from(r in AlertRule, where: r.product_key == ^product_key))
  end

  defp create_rule_alert(device, rule) do
    # Check if active alert for this rule exists to avoid spam
    exists =
      Repo.exists?(
        from(a in Alert,
          where: a.device_id == ^device.id and a.rule_id == ^rule.id and a.status == "active"
        )
      )

    unless exists do
      %Alert{}
      |> Alert.changeset(%{
        device_id: device.id,
        rule_id: rule.id,
        type: "threshold",
        status: "active",
        message: "Rule Breach: #{rule.condition_field} #{rule.operator} #{rule.threshold_value}",
        triggered_at: DateTime.utc_now()
      })
      |> Repo.insert()
    end
  end
end
