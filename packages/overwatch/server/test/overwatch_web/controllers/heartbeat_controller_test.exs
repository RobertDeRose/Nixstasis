defmodule NixstasisWeb.HeartbeatControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices

  setup do
    {:ok, device} = Devices.register_device(%{mac_address: "HB1", product_key: "P1"})
    # Need to approve it
    {:ok, approved} = Devices.approve_device(device)
    %{device: approved}
  end

  test "POST /api/v1/devices/:id/heartbeat updates last_seen and returns commands", %{
    conn: conn,
    device: device
  } do
    # Queue a command
    {:ok, _} = Devices.queue_command(device, %{"cmd" => "update"})

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat", %{})

    assert %{"commands" => commands} = json_response(conn, 200)["data"]
    assert length(commands) == 1
    assert hd(commands)["payload"] == %{"cmd" => "update"}

    # Verify last_seen updated
    updated = Devices.get_device!(device.id)
    refute is_nil(updated.last_seen_at)
  end
end
