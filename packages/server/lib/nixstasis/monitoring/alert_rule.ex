defmodule Nixstasis.Monitoring.AlertRule do
  @moduledoc """
  Resource for telemetry alert rules.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "alert_rules"
    repo Nixstasis.Repo

    custom_indexes do
      index [:name]
      index [:product_name]
    end
  end

  json_api do
    type "alert_rule"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :product_name, :condition_field, :operator, :threshold_value]
    end

    update :update do
      accept [:product_name, :condition_field, :operator, :threshold_value]
    end
  end

  attributes do
    integer_primary_key :id

    attribute :name, :string do
      allow_nil? false
      default "Untitled rule"
      constraints min_length: 1
      public? true
    end

    attribute :product_name, :string do
      allow_nil? false
      public? true
    end

    attribute :condition_field, :string do
      allow_nil? false
      public? true
    end

    attribute :operator, Nixstasis.Types.RuleOperator do
      allow_nil? false
      public? true
    end

    attribute :threshold_value, :string do
      allow_nil? false
      public? true
    end

    timestamps()
  end

  @number_operators [">", ">=", "=", "<=", "<", "!="]
  @string_operators ["contains", "doesn't contain", "is", "is not"]

  @doc "Builds inline validation issues for alert rule modal inputs."
  def validation_issues(schema_option_types, rule_params) when is_map(schema_option_types) and is_map(rule_params) do
    field = Map.get(rule_params, "condition_field", "")
    operator = Map.get(rule_params, "operator", "=")
    threshold = Map.get(rule_params, "threshold_value", "")
    field_type = Map.get(schema_option_types, field, "unknown")

    []
    |> maybe_add_missing_field_issue(field)
    |> maybe_add_operator_issue(field, field_type, operator)
    |> maybe_add_threshold_issue(field, field_type, threshold)
  end

  def validation_issues(_schema_option_types, _rule_params), do: []

  def operator_options_for_type("number"), do: @number_operators
  def operator_options_for_type(_), do: @string_operators

  def valid_operator_for_type?(field_type, operator) when is_binary(operator) do
    operator in operator_options_for_type(field_type)
  end

  def valid_operator_for_type?(_field_type, _operator), do: false

  def valid_threshold_for_type?("number", threshold) when is_number(threshold), do: true

  def valid_threshold_for_type?("number", threshold) when is_binary(threshold),
    do: parse_number(threshold)

  def valid_threshold_for_type?("string", threshold) when is_binary(threshold),
    do: String.trim(threshold) != ""

  def valid_threshold_for_type?("string", threshold) when is_number(threshold), do: true

  def valid_threshold_for_type?(_field_type, threshold) when is_number(threshold), do: true

  def valid_threshold_for_type?(_field_type, threshold), do: is_binary(threshold) and String.trim(threshold) != ""

  defp parse_number(threshold) do
    case Float.parse(String.trim(threshold)) do
      {_value, ""} -> true
      _ -> false
    end
  end

  defp maybe_add_missing_field_issue(issues, ""),
    do: [%{field: "condition_field", message: "Select a schema field."} | issues]

  defp maybe_add_missing_field_issue(issues, _field), do: issues

  defp maybe_add_operator_issue(issues, "", _field_type, _operator), do: issues

  defp maybe_add_operator_issue(issues, _field, field_type, operator) do
    if valid_operator_for_type?(field_type, operator) do
      issues
    else
      [%{field: "operator", message: "Operator is not valid for the selected field type."} | issues]
    end
  end

  defp maybe_add_threshold_issue(issues, "", _field_type, _threshold), do: issues

  defp maybe_add_threshold_issue(issues, _field, field_type, threshold) do
    if valid_threshold_for_type?(field_type, threshold) do
      issues
    else
      [%{field: "threshold_value", message: "Threshold value is invalid for the selected field type."} | issues]
    end
  end
end
