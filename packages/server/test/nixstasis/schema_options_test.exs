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

  describe "bounded schema references" do
    test "returns references when the catalog is within the configured limit" do
      register_schema_device(
        "bounded-thermostat",
        schema("bounded-thermostat", "v1", %{"temp" => %{"type" => "number"}})
      )

      assert {:ok, [%{schema_id: "bounded-thermostat", schema_version: "v1"}]} =
               SchemaOptions.list_bounded_schema_references()
    end

    test "fails closed when the schema reference catalog exceeds the limit" do
      limit = SchemaOptions.max_schema_references()

      Enum.each(1..(limit + 1), fn index ->
        product = "bounded-product-#{index}"
        register_schema_device(product, schema(product, "v1", %{"value" => %{"type" => "number"}}))
      end)

      assert {:error, :too_many} = SchemaOptions.list_bounded_schema_references()
    end
  end

  describe "batched schema definitions" do
    test "returns one canonical row per identity and marks divergent definitions" do
      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"temp" => %{"type" => "number"}})
      )

      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"humidity" => %{"type" => "number"}})
      )

      register_schema_device(
        "lighting",
        schema("lighting", "v1", %{"brightness" => %{"type" => "number"}})
      )

      assert [%{schema_id: "thermostat", schema_version: "v1", conflict?: true}] =
               Devices.list_canonical_schema_definitions(["thermostat"])
    end

    test "batch returns one definition per identity across many devices and references" do
      references =
        for product_number <- 1..4,
            version_number <- 1..3 do
          product = "scale-product-#{product_number}"
          version = "v#{version_number}"
          definition = schema(product, version, %{"value" => %{"type" => "number"}})

          Enum.each(1..4, fn _ -> register_schema_device(product, definition) end)
          %{schema_id: product, schema_version: version}
        end

      product_names = Enum.map(references, & &1.schema_id)
      definitions = Devices.list_canonical_schema_definitions(product_names)

      assert length(definitions) == 12
      assert Enum.all?(definitions, &(&1.conflict? == false))

      handler_id = "schema-option-batch-query-count-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:nixstasis, :repo, :query],
          fn _event, _measurements, _metadata, test_pid ->
            send(test_pid, :schema_option_batch_query)
          end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, %{options: options, errors: []}} =
               SchemaOptions.options_for_many(references, :report)

      assert length(options) == 12
      assert_receive :schema_option_batch_query
      refute_receive :schema_option_batch_query, 20
    end

    test "options_for_many fails closed for conflicting requested identities" do
      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"temp" => %{"type" => "number"}})
      )

      register_schema_device(
        "thermostat",
        schema("thermostat", "v1", %{"humidity" => %{"type" => "number"}})
      )

      assert {:ok, %{options: [], errors: [:conflict]}} =
               SchemaOptions.options_for_many(
                 [%{schema_id: "thermostat", schema_version: "v1"}],
                 :report
               )
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
