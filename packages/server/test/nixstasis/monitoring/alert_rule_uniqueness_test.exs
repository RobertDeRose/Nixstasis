defmodule Nixstasis.Monitoring.AlertRuleUniquenessTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain
  alias Nixstasis.Monitoring

  test "alert rule names are detected case-insensitively and enforced by the domain" do
    name = "Case Collision #{System.unique_integer([:positive])}"

    assert {:ok, rule} = Domain.create_rule(rule_attrs(name))
    assert Monitoring.alert_rule_name_taken?(String.downcase(name))
    refute Monitoring.alert_rule_name_taken?(String.downcase(name), rule.id)

    assert {:error, %Ash.Error.Invalid{}} = Domain.create_rule(rule_attrs(String.downcase(name)))
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
