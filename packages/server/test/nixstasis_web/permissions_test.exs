defmodule NixstasisWeb.PermissionsTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Devices.Device
  alias NixstasisWeb.Permissions

  test "script permissions can be scoped to allowed scripts" do
    session = %{
      "script_permissions" => %{
        "can_view" => true,
        "can_manage" => true
      }
    }

    assert Permissions.can_view_scripts?(session)
    assert Permissions.can_manage_scripts?(session)
  end

  test "script permissions default to false" do
    refute Permissions.can_view_scripts?(%{})
    refute Permissions.can_manage_scripts?(%{})
  end

  test "command policy permissions separate status, details, and management" do
    viewer = %{
      "command_policy_permissions" => %{
        "can_view_status" => true,
        "can_view_details" => false,
        "can_manage" => false
      }
    }

    operator = %{
      "command_policy_permissions" => %{
        "can_view_status" => true,
        "can_view_details" => true,
        "can_manage" => true
      },
      "device_permissions" => %{"can_manage" => true, "device_ids" => ["device-a"]}
    }

    assert Permissions.can_view_command_policy_status?(viewer)
    refute Permissions.can_view_command_policy_details?(viewer)
    refute Permissions.can_manage_command_policies?(viewer)

    assert Permissions.can_view_command_policy_details?(operator)
    assert Permissions.can_manage_command_policy_for_device?(operator, "device-a")
    refute Permissions.can_manage_command_policy_for_device?(operator, "device-b")

    assert Permissions.can_assign_command_policy_to_device?(operator, %Device{
             id: "device-a",
             approval_status: :approved
           })

    refute Permissions.can_assign_command_policy_to_device?(operator, %Device{id: "device-a", approval_status: :pending})
  end

  test "command policy permissions default to false" do
    refute Permissions.can_view_command_policy_status?(%{})
    refute Permissions.can_view_command_policy_details?(%{})
    refute Permissions.can_manage_command_policies?(%{})
    refute Permissions.can_manage_command_policy_for_device?(%{}, "device-a")
  end
end
