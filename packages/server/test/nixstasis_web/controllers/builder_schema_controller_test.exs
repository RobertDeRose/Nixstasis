defmodule NixstasisWeb.BuilderSchemaControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:11",
        "product_name" => "thermostat-v1",
        "schema" => %{
          "version" => "v1",
          "properties" => %{
            "temp" => %{"type" => "number"},
            "humidity" => %{"type" => "number"}
          }
        }
      })

    :ok
  end

  test "GET /api/v1/builder-schemas lists schema references", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/builder-schemas")
    body = json_response(conn, 200)

    assert %{"data" => data} = body
    assert Enum.any?(data, &(&1["schema_id"] == "thermostat-v1"))
  end

  test "GET /api/v1/builder-schemas/:id/versions/:version/options returns options", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/builder-schemas/thermostat-v1/versions/v1/options?builder=alert")
    body = json_response(conn, 200)

    assert %{"data" => %{"options" => options}} = body
    assert Enum.any?(options, &(&1["key"] == "temp"))
  end

  test "GET options returns 404 when schema missing", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/builder-schemas/unknown/versions/v1/options?builder=alert")

    assert %{"error" => %{"code" => "schema_not_found"}} = json_response(conn, 404)
  end
end
