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

    %{device: approved, command: command}
  end

  test "GET /api/v1/devices/:device_id/command_payloads/:ref returns referenced payload", %{
    conn: conn,
    device: device
  } do
    conn = get(conn, ~p"/api/v1/devices/#{device.id}/command_payloads/install-alpha")

    assert %{
             "content_type" => "text/plain",
             "name" => "alpha",
             "data" => "hello"
           } = json_response(conn, 200)
  end

  test "POST /api/v1/devices/:device_id/command_results acknowledges results", %{
    conn: conn,
    device: device,
    command: command
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

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/command_results", payload)
    assert %{"data" => %{"acknowledged_count" => 1}} = json_response(conn, 202)
  end
end
