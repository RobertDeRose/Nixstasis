defmodule Nixstasis.SchemaOptions.NormalizerTest do
  use ExUnit.Case, async: true

  alias Nixstasis.SchemaOptions.Normalizer

  test "normalizes properties-based schema with nested keys" do
    schema = %{
      "product" => "weather",
      "version" => "v1",
      "type" => "object",
      "properties" => %{
        "temp" => %{"type" => "number"},
        "sensors" => %{
          "properties" => %{
            "humidity" => %{"type" => "number"}
          }
        }
      }
    }

    options = Normalizer.normalize(schema)

    refute Enum.any?(options, &(&1.key == "product"))
    refute Enum.any?(options, &(&1.key == "version"))
    refute Enum.any?(options, &(&1.key == "type"))
    assert Enum.any?(options, &(&1.key == "temp"))
    assert Enum.any?(options, &(&1.key == "sensors.humidity"))
    assert Enum.all?(options, & &1.selectable)
  end

  test "disambiguates duplicate labels" do
    schema = %{
      "alpha" => %{"status" => "ok"},
      "beta" => %{"status" => "warn"}
    }

    options = Normalizer.normalize(schema)
    labels = Enum.map(options, & &1.label)

    assert Enum.any?(labels, &String.contains?(&1, "(alpha.status)"))
    assert Enum.any?(labels, &String.contains?(&1, "(beta.status)"))
  end
end
