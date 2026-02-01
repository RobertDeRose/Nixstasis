defmodule Nixstasis.Monitoring.RuleEvaluatorTest do
  use ExUnit.Case, async: true
  alias Nixstasis.Monitoring.RuleEvaluator

  # Mocking the schema structure for now, or we will assume it exists shortly
  defmodule RuleStruct do
    defstruct [:condition_field, :operator, :threshold_value]
  end

  describe "evaluate/2" do
    test "returns true when value is greater than threshold" do
      rule = %RuleStruct{
        condition_field: "temp",
        operator: ">",
        threshold_value: "50"
      }

      payload = %{"temp" => 51}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end

    test "returns false when value is not greater than threshold" do
      rule = %RuleStruct{
        condition_field: "temp",
        operator: ">",
        threshold_value: "50"
      }

      payload = %{"temp" => 50}

      assert RuleEvaluator.evaluate(payload, rule) == false
    end

    test "returns true when value is less than threshold" do
      rule = %RuleStruct{
        condition_field: "temp",
        operator: "<",
        threshold_value: "10"
      }

      payload = %{"temp" => 5}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end

    test "handles equality check" do
      rule = %RuleStruct{
        condition_field: "status",
        operator: "=",
        threshold_value: "active"
      }

      payload = %{"status" => "active"}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end

    test "handles equality check for numbers" do
      rule = %RuleStruct{
        condition_field: "code",
        operator: "=",
        threshold_value: "200"
      }

      payload = %{"code" => 200}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end

    test "handles inequality check" do
      rule = %RuleStruct{
        condition_field: "status",
        operator: "!=",
        threshold_value: "ok"
      }

      payload = %{"status" => "error"}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end

    test "supports nested json paths" do
      rule = %RuleStruct{
        condition_field: "sensors.cpu.temp",
        operator: ">",
        threshold_value: "80"
      }

      payload = %{"sensors" => %{"cpu" => %{"temp" => 85}}}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end

    test "returns false if field is missing" do
      rule = %RuleStruct{
        condition_field: "temp",
        operator: ">",
        threshold_value: "50"
      }

      payload = %{"other" => 10}

      assert RuleEvaluator.evaluate(payload, rule) == false
    end

    test "handles numerical comparison with string threshold in rule" do
      # Thresholds are likely stored as strings in DB if the column is generic,
      # or we might use a typed field. The spec says `threshold_value` (no type).
      # Assuming string storage for flexibility, the evaluator must cast.
      rule = %RuleStruct{
        condition_field: "temp",
        operator: ">",
        threshold_value: "50.5"
      }

      payload = %{"temp" => 51.0}

      assert RuleEvaluator.evaluate(payload, rule) == true
    end
  end
end
