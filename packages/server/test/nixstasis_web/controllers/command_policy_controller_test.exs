defmodule NixstasisWeb.CommandPolicyControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  setup %{conn: conn} do
    {:ok, device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EF:03",
        product_name: "preview-target"
      })

    {:ok, device} = Devices.approve_device(device)
    {:ok, entry} = Domain.create_command_allowlist_entry(%{name: "df", command_path: "/usr/bin/df"})

    conn =
      Plug.Test.init_test_session(conn, %{
        "command_policy_permissions" => %{
          "can_view_status" => true,
          "can_view_details" => true,
          "can_manage" => true
        },
        "device_permissions" => %{"can_view" => true, "can_manage" => true}
      })

    %{conn: conn, device: device, entry: entry}
  end

  test "preview returns effective policy for authorized approved devices", %{conn: conn, device: device, entry: entry} do
    conn =
      post(conn, ~p"/scripts/command-policies/preview", %{
        "device_ids" => [device.id],
        "entry_ids" => [entry.id],
        "current_commands" => %{}
      })

    assert %{"data" => data} = json_response(conn, 200)
    assert data["commands"] == %{"df" => "/usr/bin/df"}
    assert data["affected_device_ids"] == [device.id]
    assert data["conflicts"] == []
  end

  test "preview requires command policy management permission", %{conn: conn, device: device, entry: entry} do
    conn =
      Plug.Test.init_test_session(conn, %{
        "command_policy_permissions" => %{"can_view_status" => true},
        "device_permissions" => %{"can_view" => true, "can_manage" => true}
      })

    conn =
      post(conn, ~p"/scripts/command-policies/preview", %{
        "device_ids" => [device.id],
        "entry_ids" => [entry.id]
      })

    assert %{"error" => _} = json_response(conn, 403)
  end
end
