defmodule NixstasisWeb.DeviceCommandControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    {:ok, device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:11:22:33",
        product_name: "P1"
      })

    {:ok, approved} = Devices.approve_device(device)
    {:ok, approved, token} = Devices.issue_device_token(approved)

    {:ok, command} =
      Devices.queue_command(approved, %{
        "type" => "install_script",
        "payload_ref" => "install-alpha",
        "payload" => %{
          "content_type" => "text/plain",
          "name" => "alpha",
          "data" => "hello"
        }
      })

    %{device: approved, command: command, token: token}
  end

  test "GET /api/v1/devices/:device_id/command_payloads/:ref returns referenced payload", %{
    conn: conn,
    device: device,
    token: token
  } do
    conn = get(conn, ~p"/api/v1/devices/#{device.id}/command_payloads/install-alpha?api_key=#{token}")

    assert %{
             "content_type" => "text/plain",
             "name" => "alpha",
             "data" => "hello"
           } = json_response(conn, 200)
  end

  test "POST /api/v1/devices/:device_id/command_results acknowledges results", %{
    conn: conn,
    device: device,
    command: command,
    token: token
  } do
    payload = %{
      "results" => [
        %{
          "command_id" => command.id,
          "status" => "OK",
          "output" => %{"installed" => true}
        }
      ]
    }

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/command_results?api_key=#{token}", payload)
    assert %{"data" => %{"acknowledged_count" => 1}} = json_response(conn, 202)
  end

  test "POST /api/v1/devices/:device_id/command_results rejects missing token", %{conn: conn, device: device} do
    conn = post(conn, ~p"/api/v1/devices/#{device.id}/command_results", %{"results" => []})

    assert %{"error" => %{"code" => "missing_api_key"}} = json_response(conn, 401)
  end

  test "POST /api/v1/devices/:device_id/command_results rejects invalid token", %{conn: conn, device: device} do
    conn = post(conn, ~p"/api/v1/devices/#{device.id}/command_results?api_key=wrong", %{"results" => []})

    assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)
  end

  test "POST /api/v1/devices/:device_id/command_results rejects wrong-device token", %{conn: conn, device: device} do
    {:ok, other} = Devices.register_device(%{mac_address: "AA:BB:CC:11:22:44", product_name: "P2"})
    {:ok, other} = Devices.approve_device(other)
    {:ok, _other, other_token} = Devices.issue_device_token(other)

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/command_results?api_key=#{other_token}", %{"results" => []})

    assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)
  end

  test "GET /api/v1/devices/:device_id/command_payloads/:ref rejects missing token", %{conn: conn, device: device} do
    conn = get(conn, ~p"/api/v1/devices/#{device.id}/command_payloads/install-alpha")

    assert %{"error" => %{"code" => "missing_api_key"}} = json_response(conn, 401)
  end

  test "GET /api/v1/devices/:device_id/command_payloads/:ref rejects invalid token", %{conn: conn, device: device} do
    conn = get(conn, ~p"/api/v1/devices/#{device.id}/command_payloads/install-alpha?api_key=wrong")

    assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)
  end

  test "GET /api/v1/devices/:device_id/command_payloads/:ref rejects wrong-device token", %{conn: conn, device: device} do
    {:ok, other} = Devices.register_device(%{mac_address: "AA:BB:CC:11:22:55", product_name: "P2"})
    {:ok, other} = Devices.approve_device(other)
    {:ok, _other, other_token} = Devices.issue_device_token(other)

    conn = get(conn, ~p"/api/v1/devices/#{device.id}/command_payloads/install-alpha?api_key=#{other_token}")

    assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)
  end

  test "POST /api/v1/devices/:device_id/heartbeat rejects missing token", %{conn: conn, device: device} do
    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat", %{})

    assert %{"error" => %{"code" => "missing_api_key"}} = json_response(conn, 401)
  end

  test "POST /api/v1/devices/:device_id/heartbeat rejects invalid token", %{conn: conn, device: device} do
    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=wrong", %{})

    assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)
  end

  test "POST /api/v1/devices/:device_id/heartbeat rejects wrong-device token", %{conn: conn, device: device} do
    {:ok, other} = Devices.register_device(%{mac_address: "AA:BB:CC:11:22:66", product_name: "P2"})
    {:ok, other} = Devices.approve_device(other)
    {:ok, _other, other_token} = Devices.issue_device_token(other)

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{other_token}", %{})

    assert %{"error" => %{"code" => "invalid_api_key"}} = json_response(conn, 401)
  end

  test "POST /api/v1/devices/:device_id/heartbeat returns 429 over rate limit", %{
    conn: conn,
    device: device,
    token: token
  } do
    Application.put_env(:nixstasis, :heartbeat_rate_limit, limit: 1, window_ms: 60_000)
    on_exit(fn -> Application.delete_env(:nixstasis, :heartbeat_rate_limit) end)

    assert post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})
           |> json_response(200)

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

    assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
  end

  test "approved device without token hash cannot use runtime endpoints", %{conn: conn} do
    {:ok, device} = Devices.register_device(%{mac_address: "AA:BB:CC:11:22:77", product_name: "P3"})
    {:ok, approved} = Devices.approve_device(device)
    assert is_nil(approved.api_token_hash)

    heartbeat = post(conn, ~p"/api/v1/devices/#{approved.id}/heartbeat?api_key=anything", %{})
    assert %{"error" => %{"code" => "missing_api_key"}} = json_response(heartbeat, 401)

    results = post(conn, ~p"/api/v1/devices/#{approved.id}/command_results?api_key=anything", %{"results" => []})
    assert %{"error" => %{"code" => "missing_api_key"}} = json_response(results, 401)

    payload = get(conn, ~p"/api/v1/devices/#{approved.id}/command_payloads/ref?api_key=anything")
    assert %{"error" => %{"code" => "missing_api_key"}} = json_response(payload, 401)
  end
end
