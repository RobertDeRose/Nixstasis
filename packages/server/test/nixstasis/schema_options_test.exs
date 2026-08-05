defmodule Nixstasis.SchemaOptionsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.SchemaOptions

  describe "get_schema_definition/2" do
    test "returns the canonical definition for one product/version pair" do
      schema = schema("thermostat", "v1", %{"temp" => %{"type" => "number"}})
      register_schema_device("thermostat", schema)

      assert {:ok, ^schema} = Devices.get_schema_definition("thermostat", "v1")
    end

    test "returns one definition when matching devices advertise identical schemas" do
      schema = schema("thermostat", "v1", %{"temp" => %{"type" => "number"}})
      register_schema_device("thermostat", schema)
      register_schema_device("thermostat", schema)

      assert {:ok, ^schema} = Devices.get_schema_definition("thermostat", "v1")
    end

    test "fails closed when matching devices advertise divergent schemas" do
      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"temp" => %{"type" => "number"}})
      )

      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"humidity" => %{"type" => "number"}})
      )

      assert {:error, :conflict} = Devices.get_schema_definition("thermostat", "v1")
    end

    test "returns not found when no readable schema matches" do
      assert {:error, :not_found} = Devices.get_schema_definition("missing", "v1")
    end
  end

  describe "conflict propagation" do
    setup do
      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"temp" => %{"type" => "number"}})
      )

      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"humidity" => %{"type" => "number"}})
      )

      :ok
    end

    test "options_for returns a typed conflict result" do
      assert {:error, :conflict} = SchemaOptions.options_for("thermostat", "v1", :alert)
    end

    test "validation blocks selections with a schema conflict issue" do
      assert %{
               valid: false,
               issues: [
                 %{
                   issue_code: "schema_conflict",
                   blocking: true,
                   slot_id: nil
                 }
               ],
               cleared_slot_ids: []
             } =
               SchemaOptions.validate_selections(:report, "thermostat", "v1", [
                 %{"slot_id" => "field", "selected_key" => "temp"}
               ])
    end
  end

  defp register_schema_device(product, schema) do
    hex_suffix =
      System.unique_integer([:positive])
      |> rem(0xFFFFFF)
      |> Integer.to_string(16)
      |> String.pad_leading(6, "0")
      |> String.graphemes()
      |> Enum.chunk_every(2)
      |> Enum.join(":")

    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "02:00:00:" <> hex_suffix,
        "product_name" => product,
        "schema" => schema
      })
  end

  defp schema(product, version, properties) do
    %{
      "product" => product,
      "version" => version,
      "properties" => properties
    }
  end
end
