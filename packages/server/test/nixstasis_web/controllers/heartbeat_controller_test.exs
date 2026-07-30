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

  test "heartbeat defers oversized command policy payloads behind payload_ref", %{
    conn: conn,
    device: device,
    token: token
  } do
    commands =
      1..250
      |> Map.new(fn index -> {"cmd#{index}", "/usr/bin/tool#{index}"} end)

    {:ok, assignment} =
      Domain.create_command_policy_assignment(%{
        device_id: device.id,
        revision: 7,
        version: "policy-large",
        resolved_policy: %{"commands" => commands}
      })

    assert {:ok, _} = Devices.queue_command_policy_assignment(assignment)

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

    assert %{"commands" => [command]} = json_response(conn, 200)["data"]
    assert command["type"] == "apply_command_policy"
    assert command["payload_ref"] == assignment.id
    refute Map.has_key?(command, "payload")
  end

  test "heartbeat includes command inventory probe manifest", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, command} =
      Domain.create_command_catalog_command(%{
        name: "df",
        display_name: "Disk free",
        category_slugs: ["diagnostics"],
        active: true
      })

    {:ok, _mapping} =
      Domain.create_command_catalog_mapping(%{
        catalog_command_id: command.id,
        os_family: "debian",
        package_manager: "apt",
        package_name: "coreutils",
        command_path: "/usr/bin/df"
      })

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{})

    assert %{"command_inventory_probe" => probe} = json_response(conn, 200)["data"]
    assert probe["catalog_version"] == "catalog-v1"
    assert "coreutils" in probe["package_names"]
    assert Enum.any?(probe["command_probes"], &(&1["name"] == "df" and &1["command_path"] == "/usr/bin/df"))
  end

  test "heartbeat persists command inventory outside telemetry", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, command} =
      Domain.create_command_catalog_command(%{
        name: "df",
        display_name: "Disk free",
        category_slugs: ["diagnostics"],
        active: true
      })

    {:ok, _mapping} =
      Domain.create_command_catalog_mapping(%{
        catalog_command_id: command.id,
        os_family: "debian",
        package_manager: "apt",
        package_name: "coreutils",
        command_path: "/usr/bin/df"
      })

    future_observed_at = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

    payload = %{
      "telemetry" => %{
        "scripts" => %{"disk" => %{"data" => %{"usage_pct" => 73.2}}},
        "command_inventory" => %{"packages" => %{"leak" => true}}
      },
      "command_inventory" => %{
        "schema_version" => 1,
        "probe_catalog_version" => "catalog-v1",
        "observed_at" => future_observed_at,
        "architecture" => "x86_64",
        "package_manager" => "apt",
        "os_release" => %{"ID" => "ubuntu", "ID_LIKE" => "debian", "UNTRUSTED" => "ignored"},
        "packages" => %{"coreutils" => %{"installed" => true}, "client-only" => %{"installed" => true}},
        "commands" => %{"df" => %{"path" => "/usr/bin/df"}, "evil" => %{"path" => "/bin/sh"}}
      }
    }

    conn = post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", payload)
    assert json_response(conn, 200)["data"]

    snapshots = Domain.list_device_command_inventory_snapshots() |> elem(1)
    assert [snapshot] = Enum.filter(snapshots, &(&1.device_id == device.id))
    assert snapshot.probe_catalog_version == "catalog-v1"
    assert DateTime.compare(snapshot.observed_at, future_observed_at) == :lt
    assert snapshot.os_family == "debian"
    assert snapshot.packages == %{"coreutils" => %{"installed" => true}}
    assert snapshot.commands == %{"df" => %{"path" => "/usr/bin/df"}}

    telemetry =
      Telemetry
      |> Ash.Query.filter(device_id == ^device.id)
      |> Ash.read!(domain: Domain)

    refute Map.has_key?(hd(telemetry).payload, "command_inventory")
  end

  test "malformed command inventory does not block heartbeat commands", %{
    conn: conn,
    device: device,
    token: token
  } do
    {:ok, _} = Devices.queue_command(device, %{"cmd" => "update"})

    conn =
      post(conn, ~p"/api/v1/devices/#{device.id}/heartbeat?api_key=#{token}", %{
        "command_inventory" => %{
          "schema_version" => "bad",
          "probe_catalog_version" => "catalog-v1"
        }
      })

    assert %{"commands" => [command]} = json_response(conn, 200)["data"]
    assert command["payload"] == %{"cmd" => "update"}

    snapshots = Domain.list_device_command_inventory_snapshots() |> elem(1)
    refute Enum.any?(snapshots, &(&1.device_id == device.id))
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
