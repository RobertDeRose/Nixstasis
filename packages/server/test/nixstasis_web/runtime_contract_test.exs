defmodule NixstasisWeb.RuntimeContractTest do
  use ExUnit.Case, async: true

  test "tls approval route remains on the canonical path" do
    routes = NixstasisWeb.Router.__routes__()

    assert Enum.any?(routes, fn route ->
             route.path == "/api/v1/check_domain" and route.verb == :get
           end)
  end
end
