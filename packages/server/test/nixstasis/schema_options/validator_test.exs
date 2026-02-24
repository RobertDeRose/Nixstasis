defmodule Nixstasis.SchemaOptions.ValidatorTest do
  use ExUnit.Case, async: true

  alias Nixstasis.SchemaOptions.Validator

  test "validates selections and returns invalid slot ids" do
    selections = [
      %{"slot_id" => "f1", "selected_key" => "temp"},
      %{"slot_id" => "f2", "selected_key" => "missing"}
    ]

    options = [
      %{key: "temp"},
      %{key: "humidity"}
    ]

    result = Validator.validate(selections, options)

    assert result.valid == false
    assert result.cleared_slot_ids == ["f2"]
    assert Enum.any?(result.issues, &(&1.issue_code == "invalid_schema_field"))
  end
end
