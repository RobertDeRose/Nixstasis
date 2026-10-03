defmodule NixstasisWeb.PermissionsTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.GroupAuthorization
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

  test "actor_id prefers trusted subject and falls back to trusted email" do
    assert {:ok, "operator-1"} =
             Permissions.actor_id(%{"operator_context" => %{"subject" => "operator-1", "email" => "ops@example.com"}})

    assert {:ok, "ops@example.com"} =
             Permissions.actor_id(%{"operator_context" => %{"subject" => " ", "email" => "ops@example.com"}})
  end

  test "actor_id fails closed when no trusted actor exists and local fallback is disabled" do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)
    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    assert {:error, :missing_actor} = Permissions.actor_id(%{})
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

  test "builds trusted group authorization from operator context and device permissions" do
    first_id = Ecto.UUID.generate()
    second_id = Ecto.UUID.generate()

    session = %{
      "operator_context" => %{"subject" => "operator-1", "email" => "operator@example.com"},
      "device_permissions" => %{
        "can_manage" => true,
        "device_ids" => [first_id, second_id]
      }
    }

    assert {:ok,
            %GroupAuthorization{
              actor_id: "operator-1",
              can_manage_devices?: true,
              can_manage_all_devices?: false,
              authorized_device_ids: ids
            }} = Permissions.device_group_authorization(session)

    assert ids == MapSet.new([first_id, second_id])
  end

  test "uses trusted email fallback and fails closed without actor identity" do
    permissions = %{"can_manage" => true}

    assert {:ok, %GroupAuthorization{actor_id: "operator@example.com"}} =
             Permissions.device_group_authorization(%{
               "operator_context" => %{"subject" => " ", "email" => "operator@example.com"},
               "device_permissions" => permissions
             })

    assert {:error, :missing_actor} =
             Permissions.device_group_authorization(%{
               "operator_context" => %{},
               "device_permissions" => permissions
             })
  end

  test "fails closed when a trusted device scope contains a malformed UUID" do
    assert {:error, :invalid_device_scope} =
             Permissions.device_group_authorization(%{
               "operator_context" => %{"subject" => "operator-1"},
               "device_permissions" => %{
                 "can_manage" => true,
                 "device_ids" => [Ecto.UUID.generate(), "not-a-uuid"]
               }
             })
  end
end
