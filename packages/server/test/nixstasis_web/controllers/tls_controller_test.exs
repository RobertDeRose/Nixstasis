defmodule NixstasisWeb.TLSControllerTest do
  use NixstasisWeb.ConnCase, async: false

  alias Nixstasis.Devices

  setup do
    original_base_domain = Application.get_env(:nixstasis, :base_domain)
    original_observations = Application.get_env(:nixstasis, :tls_observations_enabled)
    original_token = System.get_env("NIXSTASIS_TLS_OBSERVATIONS_TOKEN")
    Application.put_env(:nixstasis, :base_domain, "devices.example.com")
    Application.put_env(:nixstasis, :tls_observations_enabled, true)
    System.put_env("NIXSTASIS_TLS_OBSERVATIONS_TOKEN", "test-token")

    on_exit(fn ->
      if original_base_domain do
        Application.put_env(:nixstasis, :base_domain, original_base_domain)
      else
        Application.delete_env(:nixstasis, :base_domain)
      end

      if original_observations do
        Application.put_env(:nixstasis, :tls_observations_enabled, original_observations)
      else
        Application.delete_env(:nixstasis, :tls_observations_enabled)
      end

      if original_token do
        System.put_env("NIXSTASIS_TLS_OBSERVATIONS_TOKEN", original_token)
      else
        System.delete_env("NIXSTASIS_TLS_OBSERVATIONS_TOKEN")
      end
    end)

    :ok
  end

  test "approves reserved hosts", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/check_domain?domain=auth.devices.example.com")

    assert response(conn, 204) == ""
  end

  test "approves laptop TLS validation hosts only for localhost", %{conn: conn} do
    Application.put_env(:nixstasis, :base_domain, "localhost")

    conn = get(conn, ~p"/api/v1/check_domain?domain=tls-validate-test.localhost")

    assert response(conn, 204) == ""
  end

  test "approves device hosts only when remote access is requested", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EE:FF",
        product_name: "P1",
        remote_access_requested: true
      })

    conn = get(conn, ~p"/api/v1/check_domain?domain=atom-aabbccddeeff.devices.example.com")

    assert response(conn, 204) == ""
  end

  test "denies unknown or inactive device hosts", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        mac_address: "11:22:33:44:55:66",
        product_name: "P1",
        remote_access_requested: false
      })

    conn = get(conn, ~p"/api/v1/check_domain?domain=atom-112233445566.devices.example.com")

    assert %{"error" => "The host is not permitted"} = json_response(conn, 401)
  end

  test "denies laptop TLS validation hosts outside localhost", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/check_domain?domain=tls-validate-test.devices.example.com")

    assert %{"error" => "The host is not permitted"} = json_response(conn, 401)
  end

  test "records TLS ask observations", %{conn: conn} do
    conn = put_req_header(conn, "x-nixstasis-tls-observations-token", "test-token")
    conn = delete(conn, ~p"/_nixstasis/laptop/tls_observations")
    assert response(conn, 204) == ""

    conn = get(build_conn(), ~p"/api/v1/check_domain?domain=nixstasis.devices.example.com")
    assert response(conn, 204) == ""

    conn =
      build_conn()
      |> put_req_header("x-nixstasis-tls-observations-token", "test-token")
      |> get(~p"/_nixstasis/laptop/tls_observations")

    assert %{"data" => [%{"domain" => "nixstasis.devices.example.com", "approved" => true} | _]} =
             json_response(conn, 200)
  end

  test "hides TLS ask observations when disabled", %{conn: conn} do
    Application.put_env(:nixstasis, :tls_observations_enabled, false)

    conn = get(conn, ~p"/_nixstasis/laptop/tls_observations")
    assert response(conn, 404) == ""
  end

  test "hides TLS ask observations without validation token", %{conn: conn} do
    conn = get(conn, ~p"/_nixstasis/laptop/tls_observations")
    assert response(conn, 404) == ""
  end
end
