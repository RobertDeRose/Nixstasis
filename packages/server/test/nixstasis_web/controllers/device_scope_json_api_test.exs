defmodule NixstasisWeb.DeviceScopeJSONAPITest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  setup do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    {:ok, device_a} =
      Devices.create_device(%{
        mac_address: "10:00:00:00:00:01",
        product_name: "scope-a"
      })

    {:ok, device_b} =
      Devices.create_device(%{
        mac_address: "10:00:00:00:00:02",
        product_name: "scope-b"
      })

    {:ok, command_a} = Devices.queue_command(device_a, %{"marker" => "command-a"})
    {:ok, command_b} = Devices.queue_command(device_b, %{"marker" => "command-b"})

    {:ok, telemetry_a} =
      Domain.create_telemetry_event(%{
        device_id: device_a.id,
        payload: %{"marker" => "telemetry-a"},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, telemetry_b} =
      Domain.create_telemetry_event(%{
        device_id: device_b.id,
        payload: %{"marker" => "telemetry-b"},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, alert_a} =
      Domain.create_alert(%{
        device_id: device_a.id,
        type: :offline,
        status: :active,
        message: "alert-a",
        triggered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, alert_b} =
      Domain.create_alert(%{
        device_id: device_b.id,
        type: :offline,
        status: :active,
        message: "alert-b",
        triggered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    %{
      device_a: device_a,
      device_b: device_b,
      command_a: command_a,
      command_b: command_b,
      telemetry_a: telemetry_a,
      telemetry_b: telemetry_b,
      alert_a: alert_a,
      alert_b: alert_b
    }
  end

  test "scoped viewers only read authorized device-backed collections", context do
    resources = [
      {"/api/json/devices", context.device_a.id, context.device_b.id},
      {"/api/json/pending_commands", context.command_a.id, context.command_b.id},
      {"/api/json/telemetry_events", context.telemetry_a.id, context.telemetry_b.id},
      {"/api/json/alerts", context.alert_a.id, context.alert_b.id}
    ]

    for {path, allowed_id, blocked_id} <- resources do
      body =
        context.conn
        |> recycle()
        |> scoped_get(path, [context.device_a.id])
        |> json_response(200)

      ids = body["data"] |> Enum.map(& &1["id"]) |> MapSet.new()
      assert ids == MapSet.new([allowed_id])
      refute MapSet.member?(ids, blocked_id)
    end
  end

  test "scoped viewers cannot read out-of-scope device-backed members", context do
    resources = [
      "/api/json/devices/#{context.device_b.id}",
      "/api/json/pending_commands/#{context.command_b.id}",
      "/api/json/telemetry_events/#{context.telemetry_b.id}",
      "/api/json/alerts/#{context.alert_b.id}"
    ]

    for path <- resources do
      conn =
        context.conn
        |> recycle()
        |> scoped_get(path, [context.device_a.id])

      assert conn.status in [403, 404]
    end
  end

  test "different scoped viewers cannot read each other's rows", context do
    body_a =
      context.conn
      |> scoped_get("/api/json/devices", [context.device_a.id])
      |> json_response(200)

    body_b =
      context.conn
      |> recycle()
      |> scoped_get("/api/json/devices", [context.device_b.id])
      |> json_response(200)

    assert Enum.map(body_a["data"], & &1["id"]) == [context.device_a.id]
    assert Enum.map(body_b["data"], & &1["id"]) == [context.device_b.id]
  end

  test "an explicit empty device scope grants no device-backed rows", %{conn: conn} do
    for path <- [
          "/api/json/devices",
          "/api/json/pending_commands",
          "/api/json/telemetry_events",
          "/api/json/alerts"
        ] do
      body =
        conn
        |> recycle()
        |> scoped_get(path, [])
        |> json_response(200)

      assert body["data"] == []
    end
  end

  test "malformed device scope is rejected before querying device-backed resources", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> put_req_header("x-token-device-ids", "not-a-uuid")
      |> put_trusted_proxy_auth()
      |> get("/api/json/devices")

    assert %{"errors" => [%{"code" => "forbidden"}]} = json_response(conn, 403)
  end

  test "unscoped viewers retain fleet-wide read access", context do
    body =
      context.conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> put_trusted_proxy_auth()
      |> get("/api/json/devices")
      |> json_response(200)

    ids = body["data"] |> Enum.map(& &1["id"]) |> MapSet.new()
    assert ids == MapSet.new([context.device_a.id, context.device_b.id])
  end

  defp scoped_get(conn, path, device_ids) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("x-token-user-roles", "nixstasis/viewer")
    |> put_req_header("x-token-device-ids", Enum.join(device_ids, ","))
    |> put_trusted_proxy_auth()
    |> get(path)
  end
end
