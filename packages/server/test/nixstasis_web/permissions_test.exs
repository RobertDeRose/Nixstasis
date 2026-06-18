defmodule NixstasisWeb.PermissionsTest do
  use ExUnit.Case, async: true

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
end
