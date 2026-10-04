defmodule NixstasisWeb.FrpAuthorizationControllerTest do
  use NixstasisWeb.ConnCase, async: true

  alias Nixstasis.Devices.FrpsToken

  test "a device credential cannot log in as another device", %{conn: conn} do
    device_a = Ecto.UUID.generate()
    device_b = Ecto.UUID.generate()
    token = credential(device_a)

    conn =
      post(conn, "/internal/frp/authorize?op=Login", %{
        "content" => %{
          "user" => FrpsToken.device_name(device_b),
          "metas" => %{"nixstasis_token" => token}
        }
      })

    assert %{"reject" => true} = json_response(conn, 200)
  end

  test "a device can register only HTTP proxies in its own subdomain namespace", %{conn: _conn} do
    device_id = Ecto.UUID.generate()
    device_name = FrpsToken.device_name(device_id)
    token = credential(device_id)

    allowed =
      post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{
        "content" => %{
          "user" => %{"user" => device_name, "metas" => %{"nixstasis_token" => token}},
          "proxy_name" => device_name <> "-console",
          "proxy_type" => "http",
          "subdomain" => device_name <> "-console",
          "custom_domains" => []
        }
      })

    assert %{"reject" => false, "unchange" => true} = json_response(allowed, 200)

    other_device = FrpsToken.device_name(Ecto.UUID.generate())

    rejected =
      post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{
        "content" => %{
          "user" => %{"user" => device_name, "metas" => %{"nixstasis_token" => token}},
          "proxy_name" => other_device,
          "proxy_type" => "http",
          "subdomain" => other_device,
          "custom_domains" => []
        }
      })

    assert %{"reject" => true} = json_response(rejected, 200)
  end

  test "tcpmux routes must use the device-owned proxy name as their only domain", %{conn: _conn} do
    device_id = Ecto.UUID.generate()
    device_name = FrpsToken.device_name(device_id)
    token = credential(device_id)
    proxy_name = device_name <> "-ssh"

    allowed =
      post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{
        "content" => %{
          "user" => %{"user" => device_name, "metas" => %{"nixstasis_token" => token}},
          "proxy_name" => proxy_name,
          "proxy_type" => "tcpmux",
          "multiplexer" => "httpconnect",
          "custom_domains" => [proxy_name],
          "subdomain" => ""
        }
      })

    assert %{"reject" => false} = json_response(allowed, 200)

    rejected =
      post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{
        "content" => %{
          "user" => %{"user" => device_name, "metas" => %{"nixstasis_token" => token}},
          "proxy_name" => proxy_name,
          "proxy_type" => "tcpmux",
          "multiplexer" => "httpconnect",
          "custom_domains" => [FrpsToken.device_name(Ecto.UUID.generate()) <> "-ssh"],
          "subdomain" => ""
        }
      })

    assert %{"reject" => true} = json_response(rejected, 200)
  end

  defp credential(device_id) do
    FrpsToken.for_heartbeat(%{
      id: device_id,
      remote_access_requested: true,
      remote_access_profile: "default"
    })
  end
end
