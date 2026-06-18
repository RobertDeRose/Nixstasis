defmodule NixstasisWeb.HeartbeatControllerTest do
  use NixstasisWeb.ConnCase

  import ExUnit.CaptureLog

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

    assert %{"commands" => commands} = data = json_response(conn, 200)["data"]
    refute Map.has_key?(data, "remote_access_token")
    refute Map.has_key?(data, "remote_access_requested")
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

  test "POST /api/v1/devices/:id/heartbeat returns ssh_authorize public key at top level", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, _} = Devices.queue_command(device, %{"type" => "ssh_authorize", "public_key" => "ssh-ed25519 test"})

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

    assert %{"commands" => [command]} = json_response(conn, 200)["data"]
    assert command["type"] == "ssh_authorize"
    assert command["public_key"] == "ssh-ed25519 test"
    assert command["payload"] == %{"public_key" => "ssh-ed25519 test", "type" => "ssh_authorize"}
  end

  test "heartbeat keeps inline payload when payload_ref is present", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, _} =
      Devices.queue_command(device, %{
        "type" => "run_script",
        "payload_ref" => "test-run-id",
        "payload" => %{
          "content_type" => "text/x-stary",
          "name" => "script",
          "data" => "---\nname: script\nschema:\n  type: object\n---\ndef main():\n    return {}\n"
        }
      })

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

    assert %{"commands" => [command]} = json_response(conn, 200)["data"]
    assert command["payload_ref"] == "test-run-id"
    assert command["payload"]["content_type"] == "text/x-stary"
    assert command["payload"]["data"] =~ "def main"
  end

  test "heartbeat omits remote_access_token when remote access is not requested", %{
    conn: conn,
    device: device,
    token: token
  } do
    with_env("FRPS_AUTH_TOKEN", "shared-secret", fn ->
      conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

      data = json_response(conn, 200)["data"]

      refute Map.has_key?(data, "remote_access_token")
      refute Map.has_key?(data, "remote_access_requested")
    end)
  end

  test "heartbeat includes remote_access_token when requested and configured", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, device} = Devices.set_remote_access(device, true)

    with_env("FRPS_AUTH_TOKEN", "shared-secret", fn ->
      conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

      assert %{"remote_access_token" => "shared-secret"} = data = json_response(conn, 200)["data"]
      refute Map.has_key?(data, "remote_access_requested")
    end)
  end

  test "heartbeat omits remote_access_token and logs when requested token is missing", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, device} = Devices.set_remote_access(device, true)

    without_env("FRPS_AUTH_TOKEN", fn ->
      log =
        capture_log(fn ->
          conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

          data = json_response(conn, 200)["data"]
          refute Map.has_key?(data, "remote_access_token")
          refute Map.has_key?(data, "remote_access_requested")
        end)

      assert log =~ "FRPS_AUTH_TOKEN is missing while remote access is requested"
    end)
  end

  test "heartbeat omits remote_access_token and logs when requested token is blank", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, device} = Devices.set_remote_access(device, true)

    with_env("FRPS_AUTH_TOKEN", "   ", fn ->
      log =
        capture_log(fn ->
          conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

          data = json_response(conn, 200)["data"]
          refute Map.has_key?(data, "remote_access_token")
          refute Map.has_key?(data, "remote_access_requested")
        end)

      assert log =~ "FRPS_AUTH_TOKEN is missing while remote access is requested"
    end)
  end

  defp with_env(name, value, fun) do
    previous = System.get_env(name)
    System.put_env(name, value)

    try do
      fun.()
    after
      restore_env(name, previous)
    end
  end

  defp without_env(name, fun) do
    previous = System.get_env(name)
    System.delete_env(name)

    try do
      fun.()
    after
      restore_env(name, previous)
    end
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
