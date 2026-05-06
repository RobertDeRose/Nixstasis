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
