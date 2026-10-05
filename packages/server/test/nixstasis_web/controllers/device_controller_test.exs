defmodule NixstasisWeb.DeviceControllerTest do
  use NixstasisWeb.ConnCase
  alias Nixstasis.Devices

  test "POST /api/v1/devices/register registers a new device", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:FF",
      "product_name" => "prod_123",
      "schema" => %{
        "product" => "prod_123",
        "type" => "object",
        "properties" => %{"temp" => %{"type" => "number"}}
      },
      "metadata" => %{"fw" => "1.0"}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert %{"id" => _id, "approval_status" => "pending"} = json_response(conn, 201)["data"]
  end

  test "POST /api/v1/devices/register requires enrollment proof before approved re-registration", %{conn: conn} do
    initial_params = %{
      "mac_address" => "AA:BB:CC:DD:EE:E0",
      "product_name" => "initial-client",
      "schema" => %{
        "product" => "initial-client",
        "type" => "object",
        "properties" => %{}
      }
    }

    conn = post(conn, ~p"/api/v1/devices/register", initial_params)

    assert %{
             "id" => id,
             "approval_status" => "pending",
             "registration_token" => registration_token
           } = json_response(conn, 201)["data"]

    assert is_binary(registration_token)
    refute Map.has_key?(json_response(conn, 201)["data"], "api_token")

    pending = Devices.get_device!(id)
    enrollment_hash = pending.api_token_hash
    assert is_binary(enrollment_hash)

    assert {:ok, approved} = Devices.approve_device(pending)
    assert approved.api_token_hash == enrollment_hash
    assert Devices.authenticate_device(approved, registration_token) == {:error, :invalid_token}

    attack_params = %{
      initial_params
      | "product_name" => "attacker-controlled",
        "schema" => %{
          "product" => "attacker-controlled",
          "type" => "object",
          "properties" => %{}
        }
    }

    attack_params = Map.put(attack_params, "remote_access_requested", true)

    attack_conn =
      conn
      |> recycle()
      |> post(~p"/api/v1/devices/register", attack_params)

    assert response(attack_conn, 403)

    unchanged = Devices.get_device!(id)
    assert unchanged.product_name == "initial-client"
    assert unchanged.remote_access_requested == false
    assert unchanged.api_token_hash == enrollment_hash

    approved_params =
      initial_params
      |> Map.put("registration_token", registration_token)
      |> Map.put("product_name", "updated-client")
      |> Map.put("schema", %{
        "product" => "updated-client",
        "type" => "object",
        "properties" => %{}
      })
      |> Map.put("remote_access_requested", true)

    approved_conn =
      attack_conn
      |> recycle()
      |> post(~p"/api/v1/devices/register", approved_params)

    assert %{
             "id" => ^id,
             "approval_status" => "approved",
             "api_token" => api_token
           } = json_response(approved_conn, 201)["data"]

    refute Map.has_key?(json_response(approved_conn, 201)["data"], "registration_token")
    assert is_binary(api_token)
    assert api_token != ""

    updated = Devices.get_device!(id)
    assert updated.product_name == "updated-client"
    assert updated.remote_access_requested == false
    assert Devices.authenticate_device(updated, api_token) == :ok
    assert Devices.authenticate_device(updated, registration_token) == {:error, :invalid_token}
  end

  test "GET /api/v1/devices requires operator identity and enforces device scope", %{conn: conn} do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn ->
      Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous)
    end)

    {:ok, allowed} =
      Devices.create_device(%{
        mac_address: "10:00:00:00:00:01",
        product_name: "allowed-runtime-list"
      })

    {:ok, denied} =
      Devices.create_device(%{
        mac_address: "10:00:00:00:00:02",
        product_name: "denied-runtime-list"
      })

    assert conn |> get(~p"/api/v1/devices") |> response(403)

    body =
      build_conn()
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> put_req_header("x-token-device-ids", allowed.id)
      |> put_trusted_proxy_auth()
      |> get(~p"/api/v1/devices")
      |> json_response(200)

    assert Enum.map(body["data"], & &1["id"]) == [allowed.id]
    refute Enum.any?(body["data"], &(&1["id"] == denied.id))

    malformed_conn =
      build_conn()
      |> put_req_header("x-token-user-roles", "nixstasis/viewer")
      |> put_req_header("x-token-device-ids", "not-a-uuid")
      |> put_trusted_proxy_auth()
      |> get(~p"/api/v1/devices")

    assert response(malformed_conn, 403)
  end

  test "GET /api/v1/devices filters by product/account/approval status", %{conn: conn} do
    {:ok, _} =
      Devices.create_device(%{
        mac_address: "11:11:11:11:11:11",
        product_name: "Alpha",
        account_number: "11111",
        approval_status: :pending
      })

    {:ok, _} =
      Devices.create_device(%{
        mac_address: "22:22:22:22:22:22",
        product_name: "Beta",
        account_number: "22222",
        approval_status: :approved
      })

    conn = get(conn, ~p"/api/v1/devices?product=Alpha&account_number=11111&approval_status=pending")
    body = json_response(conn, 200)

    assert length(body["data"]) == 1
    assert hd(body["data"])["mac_address"] == "11:11:11:11:11:11"
    assert body["meta"]["active_filters"]["product"] == "Alpha"
    assert body["meta"]["active_filters"]["approval_status"] == "pending"
  end

  test "POST /api/v1/devices/register rejects schema missing product", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F1",
      "product_name" => "prod_123",
      "schema" => %{"type" => "object", "properties" => %{}}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]
  end

  test "POST /api/v1/devices/register rejects missing schema", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F2",
      "product_name" => "prod_123"
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]
  end

  test "POST /api/v1/devices/register rejects nil schema", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F4",
      "product_name" => "prod_123",
      "schema" => nil
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]
  end

  test "POST /api/v1/devices/register rejects empty schema_definition", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F3",
      "product_name" => "prod_123",
      "schema_definition" => %{}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]
  end

  test "POST /api/v1/devices/register rejects empty direct schema", %{conn: conn} do
    params = %{
      "mac_address" => "AA:BB:CC:DD:EE:F5",
      "product_name" => "prod_123",
      "schema" => %{}
    }

    conn = post(conn, ~p"/api/v1/devices/register", params)

    assert json_response(conn, 422)["errors"]
  end

  test "GET /api/v1/devices filters by connectivity status", %{conn: conn} do
    {:ok, _} =
      Devices.create_device(%{
        mac_address: "55:55:55:55:55:55",
        product_name: "Alpha",
        last_seen_at: DateTime.utc_now()
      })

    {:ok, _} =
      Devices.create_device(%{
        mac_address: "66:66:66:66:66:66",
        product_name: "Beta",
        last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute)
      })

    conn = get(conn, ~p"/api/v1/devices?connectivity_status=offline")
    body = json_response(conn, 200)

    assert length(body["data"]) == 1
    assert hd(body["data"])["mac_address"] == "66:66:66:66:66:66"
    assert body["meta"]["active_filters"]["connectivity_status"] == "offline"
  end

  test "POST /api/v1/devices/:device_id/modal is obsolete", %{conn: conn} do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: "33:33:33:33:33:33",
        product_name: "Alpha"
      })

    conn = post(conn, "/api/v1/devices/#{device.id}/modal")
    assert response(conn, 404)
    assert Devices.get_device!(device.id).remote_access_requested == false
  end

  test "DELETE /api/v1/devices/:device_id/modal is obsolete", %{conn: conn} do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: "44:44:44:44:44:44",
        product_name: "Alpha",
        remote_access_requested: true
      })

    conn = delete(conn, "/api/v1/devices/#{device.id}/modal")
    assert response(conn, 404)
    assert Devices.get_device!(device.id).remote_access_requested == true
  end
end
