defmodule Nixstasis.DeploymentTest do
  use ExUnit.Case, async: false

  alias Nixstasis.Deployment

  setup do
    original_base_domain = Application.get_env(:nixstasis, :base_domain)
    original_port = System.get_env("PORT")

    Application.put_env(:nixstasis, :base_domain, "devices.example.com")

    on_exit(fn ->
      if original_base_domain do
        Application.put_env(:nixstasis, :base_domain, original_base_domain)
      else
        Application.delete_env(:nixstasis, :base_domain)
      end

      if original_port do
        System.put_env("PORT", original_port)
      else
        System.delete_env("PORT")
      end
    end)

    :ok
  end

  test "port/0 defaults to the canonical internal port" do
    System.delete_env("PORT")

    assert Deployment.port() == 4000
  end

  test "port/0 accepts explicit overrides" do
    System.put_env("PORT", "4010")

    assert Deployment.port() == 4010
  end

  test "approved_tls_domain?/1 accepts reserved hosts and remote-access device hosts" do
    assert Deployment.approved_tls_domain?("auth.devices.example.com")
    assert Deployment.approved_tls_domain?("nixstasis.devices.example.com")

    assert Deployment.approved_tls_domain?(
             "atom-aabbccddeeff.devices.example.com",
             fn mac -> mac == "AA:BB:CC:DD:EE:FF" end
           )
  end

  test "approved_tls_domain?/1 rejects non-matching domains" do
    refute Deployment.approved_tls_domain?("frp-router.devices.example.com")
    refute Deployment.approved_tls_domain?("atom-aabbccddeeff.other.example.com")
  end
end
