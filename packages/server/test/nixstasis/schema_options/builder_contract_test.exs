defmodule Nixstasis.SchemaOptions.BuilderContractTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:99",
        "product_name" => "shape-v1",
        "schema" => %{
          "product" => "shape-v1",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    :ok
  end

  test "list_builder_schema_references returns schema references" do
    refs = Domain.list_builder_schema_references!()

    assert Enum.any?(refs, &(&1.schema_id == "shape-v1"))
  end

  test "get_builder_schema_options returns an encodable success map" do
    result = Domain.get_builder_schema_options!("shape-v1", "v1", "alert")

    assert %{status: :ok, payload: %{schema_id: "shape-v1", options: options}} = result
    assert Enum.any?(options, &(&1.key == "temp"))
    assert {:ok, _json} = Jason.encode(result)
  end

  test "get_builder_schema_options returns an encodable error map" do
    result = Domain.get_builder_schema_options!("missing", "v1", "alert")

    assert result == %{status: :error, reason: :not_found}
    assert {:ok, _json} = Jason.encode(result)
  end

  test "validate_builder_configuration returns validation details" do
    result =
      Domain.validate_builder_configuration!("report", "shape-v1", "v1", [
        %{"slot_id" => "a", "selected_key" => "missing"}
      ])

    assert %{valid: false, cleared_slot_ids: ["a"]} = result
  end
end
