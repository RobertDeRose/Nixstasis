defmodule Nixstasis.Devices.SchemaValidatorTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Devices.SchemaValidator

  test "accepts registration schema with required product and properties" do
    assert :ok ==
             SchemaValidator.validate_registration(%{
               "product" => "thermostat",
               "type" => "object",
               "properties" => %{"temp" => %{"type" => "number"}}
             })
  end

  test "rejects registration schema missing product" do
    assert {:error, message} =
             SchemaValidator.validate_registration(%{
               "type" => "object",
               "properties" => %{"temp" => %{"type" => "number"}}
             })

    assert message =~ "product"
  end

  test "rejects malformed registration schema properties" do
    assert {:error, message} =
             SchemaValidator.validate_registration(%{
               "product" => "thermostat",
               "type" => "object",
               "properties" => []
             })

    assert message =~ "properties"
  end

  test "rejects nil public registration schema" do
    assert {:error, message} = SchemaValidator.validate_registration(nil)

    assert message =~ "JSON object"
  end

  test "rejects empty public registration schema" do
    assert {:error, message} = SchemaValidator.validate_registration(%{})

    assert message =~ "product"
  end

  test "allows internal registration with empty schema" do
    assert :ok == SchemaValidator.validate_registration(%{}, :internal)
  end

  test "rejects registration schemas over the field-count limit" do
    max_fields = SchemaValidator.limits().max_fields

    assert {:error, message} =
             SchemaValidator.validate_registration(%{
               "product" => "thermostat",
               "type" => "object",
               "properties" =>
                 Map.new(1..(max_fields + 1), fn index ->
                   {"field_#{index}", %{"type" => "number"}}
                 end)
             })

    assert message =~ "maximum field count"
  end

  test "rejects registration schemas over the nesting-depth limit" do
    max_depth = SchemaValidator.limits().max_depth

    nested_properties =
      Enum.reduce(1..(max_depth + 1), %{"type" => "number"}, fn index, schema ->
        %{"level_#{index}" => %{"type" => "object", "properties" => schema}}
      end)

    assert {:error, message} =
             SchemaValidator.validate_registration(%{
               "product" => "thermostat",
               "type" => "object",
               "properties" => nested_properties
             })

    assert message =~ "maximum nesting depth"
  end

  test "rejects registration schemas over the encoded-size limit" do
    max_bytes = SchemaValidator.limits().max_bytes
    oversized_value = String.duplicate("x", max_bytes)

    assert {:error, message} =
             SchemaValidator.validate_registration(%{
               "product" => "thermostat",
               "type" => "object",
               "properties" => %{"description" => %{"type" => "string", "default" => oversized_value}}
             })

    assert message =~ "maximum size"
  end

  test "register_device persists schema_definition as schema" do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:88",
        "product_name" => "thermostat",
        "schema_definition" => %{
          "product" => "thermostat",
          "type" => "object",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    assert device.schema["product"] == "thermostat"
    assert device.schema["properties"]["temp"]["type"] == "number"
  end

  test "register_device rejects malformed schema_definition" do
    assert {:error, %Ash.Error.Invalid{} = error} =
             Devices.register_device(%{
               "mac_address" => "AA:BB:CC:DD:EE:89",
               "product_name" => "thermostat",
               "schema_definition" => %{"type" => "object", "properties" => %{}}
             })

    assert Exception.message(error) =~ "product"
  end

  test "register_device rejects malformed direct schema payload" do
    assert {:error, %Ash.Error.Invalid{} = error} =
             Devices.register_device(%{
               "mac_address" => "AA:BB:CC:DD:EE:90",
               "product_name" => "thermostat",
               "schema" => %{"type" => "object", "properties" => %{}}
             })

    assert Exception.message(error) =~ "product"
  end
end
