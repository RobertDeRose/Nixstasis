defmodule NixstasisWeb.DeviceRuntimeJSONAPITest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices
  alias NixstasisWeb.Plugs.JsonApiPermissions

  setup do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    {:ok, pending} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:01",
        product_name: "runtime-pending",
        approval_status: :pending,
        ipv4_address: "192.0.2.10"
      })

    {:ok, approved} =
      Devices.create_device(%{
        mac_address: "AA:BB:CC:DD:EE:02",
        product_name: "runtime-approved",
        account_number: "12345",
        approval_status: :approved,
        ipv4_address: "192.0.2.11",
        last_seen_at: DateTime.utc_now()
      })

    {:ok, approved, token} = Devices.issue_device_token(approved)

    %{pending: pending, approved: approved, token: token}
  end

  test "generated list uses the device filters and active-filter metadata", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> get(
        "/api/json/device_runtime/devices?product=runtime-approved&account_number=12345&approval_status=approved&connectivity_status=online&ipv4_address=192.0.2.11"
      )

    assert %{
             "data" => [%{"mac_address" => "AA:BB:CC:DD:EE:02"}],
             "meta" => %{
               "active_filters" => %{
                 "product" => "runtime-approved",
                 "account_number" => "12345",
                 "approval_status" => "approved",
                 "connectivity_status" => "online",
                 "ipv4_address" => "192.0.2.11"
               }
             }
           } = json_response(conn, 200)
  end

  test "generated list omits blank and invalid active filters", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> get("/api/json/device_runtime/devices?product=%20&approval_status=unknown&ipv4_address=%20")

    assert %{"data" => data, "meta" => %{"active_filters" => %{}}} = json_response(conn, 200)
    assert length(data) == 2
  end

  test "generated list uses the operator permission boundary", %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> get("/api/json/device_runtime/devices")

    assert %{"errors" => [%{"code" => "forbidden"}]} = json_response(conn, 403)
  end

  test "generated registration is public and returns pending devices without a token", %{conn: conn} do
    params = %{
      "data" => %{
        "mac_address" => "AA:BB:CC:DD:EE:03",
        "product_name" => "runtime-new",
        "schema_definition" => %{"product" => "runtime-new", "type" => "object", "properties" => %{}},
        "ipv4_address" => "192.0.2.12"
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/register", params)

    body = json_response(conn, 201)

    assert %{
             "data" => %{
               "approval_status" => "pending",
               "mac_address" => "AA:BB:CC:DD:EE:03"
             }
           } = body

    refute body["data"]["api_token"]
  end

  test "generated registration rotates an approved device token", %{conn: conn, approved: approved, token: old_token} do
    params = %{
      "data" => %{
        "mac_address" => approved.mac_address,
        "product_name" => approved.product_name,
        "schema" => %{"product" => approved.product_name, "type" => "object", "properties" => %{}}
      }
    }

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/register", params)

    body = json_response(conn, 201)
    new_token = body["data"]["api_token"]

    assert body["data"]["id"] == approved.id
    assert body["data"]["approval_status"] == "approved"
    assert is_binary(new_token) and new_token != ""
    assert new_token != old_token

    {:ok, updated} = Devices.get_device(approved.id)
    assert {:error, :invalid_token} = Devices.authenticate_device(updated, old_token)
    assert :ok = Devices.authenticate_device(updated, new_token)
  end

  test "generated registration returns a JSON:API validation error for a missing schema", %{conn: conn} do
    params = %{"data" => %{"mac_address" => "AA:BB:CC:DD:EE:04"}}

    conn =
      conn
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")
      |> post("/api/json/device_runtime/devices/register", params)

    assert is_list(json_response(conn, 400)["errors"])
  end

  test "device runtime HTTP permission returns 404 before authentication for an unknown device", %{conn: conn} do
    conn = get(conn, "/api/json/device_runtime/devices/#{Ecto.UUID.generate()}/heartbeat?api_key=wrong")

    assert %{"errors" => [%{"code" => "device_not_found"}]} = json_response(conn, 404)
  end

  test "device runtime HTTP permission rejects missing keys", %{conn: conn, approved: approved} do
    conn = get(conn, "/api/json/device_runtime/devices/#{approved.id}/heartbeat")

    assert %{"errors" => [%{"code" => "missing_api_key"}]} = json_response(conn, 401)
  end

  test "device runtime HTTP permission rejects unapproved devices", %{conn: conn, pending: pending} do
    conn = get(conn, "/api/json/device_runtime/devices/#{pending.id}/heartbeat?api_key=anything")

    assert %{"errors" => [%{"code" => "device_not_approved"}]} = json_response(conn, 403)
  end

  test "device runtime permission sets the approved device as the Ash actor", %{
    conn: conn,
    approved: approved,
    token: token
  } do
    conn = runtime_permission_conn(conn, approved.id, %{"api_key" => token})
    conn = JsonApiPermissions.call(conn, [])

    refute conn.halted
    assert Ash.PlugHelpers.get_actor(conn).id == approved.id
  end

  defp runtime_permission_conn(conn, device_id, query_params) do
    conn
    |> Map.put(:method, "POST")
    |> Map.put(:path_info, ["api", "json", "device_runtime", "devices", device_id, "heartbeat"])
    |> Map.put(:path_params, %{"device_id" => device_id})
    |> Map.put(:query_params, query_params)
  end
end
