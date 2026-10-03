defmodule NixstasisWeb.BuilderSchemaControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:11",
        "product_name" => "thermostat-v1",
        "schema" => %{
          "product" => "thermostat-v1",
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

    assert %{"data" => %{"load_time_ms" => load_time_ms, "options" => options}} = body
    assert load_time_ms >= 0
    assert Enum.any?(options, &(&1["key"] == "temp"))
  end

  test "GET options returns 404 when schema missing", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/builder-schemas/unknown/versions/v1/options?builder=alert")

    assert %{"error" => %{"code" => "schema_not_found"}} = json_response(conn, 404)
  end

  test "GET options fails closed when matching schemas diverge", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:12",
        "product_name" => "thermostat-v1",
        "schema" => %{
          "product" => "thermostat-v1",
          "version" => "v1",
          "properties" => %{"pressure" => %{"type" => "number"}}
        }
      })

    conn = get(conn, ~p"/api/v1/builder-schemas/thermostat-v1/versions/v1/options?builder=alert")

    assert %{"error" => %{"code" => "schema_conflict"}} = json_response(conn, 409)
  end

  test "legacy wrapper remains available outside JSON:API permission checks", %{conn: conn} do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    conn = get(conn, ~p"/api/v1/builder-schemas")

    assert %{"data" => data} = json_response(conn, 200)
    assert Enum.any?(data, &(&1["schema_id"] == "thermostat-v1"))
  end
end
