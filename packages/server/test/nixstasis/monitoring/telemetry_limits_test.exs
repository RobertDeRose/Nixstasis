defmodule Nixstasis.Monitoring.TelemetryLimitsTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Monitoring.TelemetryLimits

  test "accepts a representative telemetry payload" do
    payload = %{
      "device" => %{"uptime_seconds" => 1234},
      "scripts" => %{
        "disk" => %{"data" => %{"status" => "ok", "usage_pct" => 73.2}}
      },
      "meta" => %{"errors" => [], "duration" => "12ms"}
    }

    assert :ok = TelemetryLimits.validate(payload)
  end

  test "rejects encoded payloads larger than the persistence budget" do
    payload = %{"chunks" => List.duplicate(String.duplicate("x", 14_000), 5)}

    assert {:error, message} = TelemetryLimits.validate(payload)
    assert message =~ "maximum encoded size"
  end

  test "rejects excessive nesting" do
    max_depth = TelemetryLimits.limits().max_depth
    payload = Enum.reduce(1..(max_depth + 1), "leaf", fn index, acc -> %{to_string(index) => acc} end)

    assert {:error, message} = TelemetryLimits.validate(payload)
    assert message =~ "nesting depth"
  end

  test "rejects excessive total key cardinality" do
    max_keys = TelemetryLimits.limits().max_total_keys

    payload =
      1..5
      |> Map.new(fn group ->
        values = Map.new(1..div(max_keys, 4), fn index -> {"k#{group}-#{index}", index} end)
        {"group#{group}", values}
      end)

    assert {:error, message} = TelemetryLimits.validate(payload)
    assert message =~ "total key count"
  end

  test "rejects oversized arrays, strings, and keys" do
    limits = TelemetryLimits.limits()

    assert {:error, array_message} =
             TelemetryLimits.validate(%{"values" => List.duplicate(1, limits.max_array_items + 1)})

    assert array_message =~ "array"

    assert {:error, string_message} =
             TelemetryLimits.validate(%{"value" => String.duplicate("x", limits.max_string_bytes + 1)})

    assert string_message =~ "string"

    assert {:error, key_message} =
             TelemetryLimits.validate(%{String.duplicate("k", limits.max_key_bytes + 1) => true})

    assert key_message =~ "key"
  end
end
