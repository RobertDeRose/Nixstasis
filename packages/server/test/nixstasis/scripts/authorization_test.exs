defmodule Nixstasis.Scripts.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Scripts.Authorization

  test "manage access gates script authoring actions" do
    assert Authorization.can_create?(%{"script_permissions" => %{"can_manage" => true}})
    assert Authorization.can_validate?(%{"script_permissions" => %{"can_manage" => true}})
    refute Authorization.can_edit?(%{"script_permissions" => %{"can_manage" => false}})
  end

  test "view access is separate from manage access" do
    assert Authorization.can_view?(%{"script_permissions" => %{"can_view" => true}})
    refute Authorization.can_manage?(%{"script_permissions" => %{"can_view" => true}})
  end
end
