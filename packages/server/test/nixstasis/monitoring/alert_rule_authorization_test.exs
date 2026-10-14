defmodule Nixstasis.Monitoring.AlertRuleAuthorizationTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.AlertRule

  @viewer %{can_view_alert_rules: true, can_manage_alert_rules: false}
  @manager %{can_view_alert_rules: true, can_manage_alert_rules: true}

  test "actor-aware alert rule writes require management capability" do
    assert {:error, _reason} =
             AlertRule
             |> Ash.Changeset.for_create(:create, rule_attrs("Viewer denied"),
               actor: @viewer,
               authorize?: true
             )
             |> Ash.create(domain: Domain)

    assert {:ok, rule} =
             AlertRule
             |> Ash.Changeset.for_create(:create, rule_attrs("Manager allowed"),
               actor: @manager,
               authorize?: true
             )
             |> Ash.create(domain: Domain)

    assert {:error, _reason} =
             rule
             |> Ash.Changeset.for_update(:update, %{threshold_value: "90"},
               actor: @viewer,
               authorize?: true
             )
             |> Ash.update(domain: Domain)

    assert {:error, _reason} = Ash.destroy(rule, actor: @viewer, authorize?: true, domain: Domain)
    assert :ok = Ash.destroy(rule, actor: @manager, authorize?: true, domain: Domain)
  end

  test "actor-aware alert rule reads require view capability" do
    assert {:ok, _rule} = Domain.create_rule(rule_attrs("Readable rule"))

    assert {:ok, [_rule]} =
             AlertRule
             |> Ash.Query.for_read(:read, %{}, actor: @viewer, authorize?: true)
             |> Ash.read(domain: Domain)

    denied_actor = %{can_view_alert_rules: false, can_manage_alert_rules: false}

    assert {:ok, []} =
             AlertRule
             |> Ash.Query.for_read(:read, %{}, actor: denied_actor, authorize?: true)
             |> Ash.read(domain: Domain)
  end

  defp rule_attrs(name) do
    %{
      name: name,
      product_name: "alert-schema-product",
      condition_field: "temp",
      operator: ">",
      threshold_value: "75"
    }
  end
end
