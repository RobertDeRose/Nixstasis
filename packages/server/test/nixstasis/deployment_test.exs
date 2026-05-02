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
    refute Deployment.approved_tls_domain?("unknown.devices.example.com")
    refute Deployment.approved_tls_domain?("atom-aabbccddeeff.other.example.com")
  end

  test "subdomain_for/1 normalizes case and trailing dots" do
    assert {:ok, "auth"} = Deployment.subdomain_for("AUTH.DEVICES.EXAMPLE.COM.")
    assert {:ok, "atom-aabbccddeeff"} = Deployment.subdomain_for("atom-aabbccddeeff.devices.example.com.")
  end

  test "approved_tls_domain?/2 normalizes device hostnames before remote-access lookup" do
    assert Deployment.approved_tls_domain?(
             "ATOM-aabbccddeeff.DEVICES.EXAMPLE.COM.",
             fn mac -> mac == "AA:BB:CC:DD:EE:FF" end
           )
  end

  test "subdomain_for/1 rejects bare base domains and nested subdomains" do
    assert :error = Deployment.subdomain_for("devices.example.com")
    assert :error = Deployment.subdomain_for("nested.auth.devices.example.com")
  end
end
