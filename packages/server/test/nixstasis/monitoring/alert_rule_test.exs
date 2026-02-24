defmodule Nixstasis.Monitoring.AlertRuleTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Monitoring.AlertRule

  test "number thresholds accept numeric runtime values" do
    schema_option_types = %{"temp" => "number"}
    params = %{"condition_field" => "temp", "operator" => ">", "threshold_value" => 51}

    assert AlertRule.validation_issues(schema_option_types, params) == []
  end

  test "string thresholds accept numeric-only values" do
    schema_option_types = %{"status" => "string"}
    params = %{"condition_field" => "status", "operator" => "is", "threshold_value" => 50}

    assert AlertRule.validation_issues(schema_option_types, params) == []
  end
end
