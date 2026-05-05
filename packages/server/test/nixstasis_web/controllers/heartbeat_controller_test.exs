defmodule NixstasisWeb.HeartbeatControllerTest do
  use NixstasisWeb.ConnCase

  require Ash.Query

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring.Telemetry

  setup do
    {:ok, device} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:FF", product_name: "P1"})

    # Need to approve it
    {:ok, approved} = Devices.approve_device(device)
    {:ok, approved, token} = Devices.issue_device_token(approved)
    %{device: approved, token: token}
  end

  test "POST /api/v1/devices/:id/heartbeat updates last_seen and returns commands", %{
    conn: conn,
    device: device,
    token: token
  } do
    # Queue a command
    {:ok, _} = Devices.queue_command(device, %{"cmd" => "update"})

    payload = %{"scripts" => %{"disk" => %{"data" => %{"usage_pct" => 73.2}}}}
    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", payload)

    assert %{"commands" => commands, "remote_access_requested" => false} = json_response(conn, 200)["data"]
    assert length(commands) == 1
    assert hd(commands)["payload"] == %{"cmd" => "update"}
    assert hd(commands)["command_id"]

    # Verify last_seen updated
    updated = Devices.get_device!(device.id)
    refute is_nil(updated.last_seen_at)

    telemetry =
      Telemetry
      |> Ash.Query.filter(device_id == ^device.id)
      |> Ash.read!(domain: Domain)

    assert length(telemetry) == 1
    assert hd(telemetry).payload["scripts"]["disk"]["data"]["usage_pct"] == 73.2
  end
end
