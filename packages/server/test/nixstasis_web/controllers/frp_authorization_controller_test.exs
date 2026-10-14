defmodule NixstasisWeb.FrpAuthorizationControllerTest do
  use NixstasisWeb.ConnCase, async: false

  import Ecto.Query

  alias Nixstasis.Devices
  alias Nixstasis.Devices.RemoteAccessLease
  alias Nixstasis.Repo
  alias Nixstasis.Devices.FrpsToken
  alias Nixstasis.Domain

  setup do
    {:ok, device} =
      Devices.create_device(%{
        mac_address: Nixstasis.Utilities.format_mac_address(Base.encode16(:crypto.strong_rand_bytes(6)))
      })

    {:ok, device} = Devices.set_remote_access(device, true)
    %{device: device, device_name: FrpsToken.device_name(device.id), token: FrpsToken.for_heartbeat(device)}
  end

  test "a device credential cannot log in as another device", %{token: token} do
    conn = login(FrpsToken.device_name(Ecto.UUID.generate()), token)
    assert %{"reject" => true} = json_response(conn, 200)
  end

  test "Login and NewProxy reject credentials after authorization is closed", context do
    assert %{"reject" => false} = json_response(login(context.device_name, context.token), 200)
    {:ok, _device} = Devices.set_remote_access(context.device, false)
    assert %{"reject" => true} = json_response(login(context.device_name, context.token), 200)
    assert %{"reject" => true} = json_response(http_proxy(context, context.device_name), 200)
  end

  test "revoked credentials cannot borrow another active lease", context do
    {:ok, second, second_id} = Devices.open_remote_access_lease(context.device)
    second_token = FrpsToken.for_heartbeat(second)
    assert %{"reject" => true} = json_response(login(context.device_name, context.token), 200)
    assert %{"reject" => false} = json_response(login(context.device_name, second_token), 200)
    :ok = Devices.close_remote_access_lease(second_id)
    assert Devices.remote_access_active?(Devices.get_device!(context.device.id))
    assert %{"reject" => true} = json_response(login(context.device_name, second_token), 200)
    assert %{"reject" => true} = json_response(http_proxy(%{context | token: second_token}, context.device_name), 200)
    assert %{"reject" => false} = json_response(login(context.device_name, context.token), 200)
  end

  test "Login and NewProxy reject expired persisted authorization", context do
    Repo.update_all(from(l in RemoteAccessLease, where: l.device_id == ^context.device.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
    )

    assert %{"reject" => true} = json_response(login(context.device_name, context.token), 200)
    assert %{"reject" => true} = json_response(http_proxy(context, context.device_name), 200)
  end

  test "a long lease cannot advertise credential validity beyond the signing maximum age" do
    now = System.system_time(:millisecond)

    {:ok, device} = Devices.create_device(%{mac_address: "02:00:00:00:90:01"})
    {:ok, device, _lease} = Devices.open_remote_access_lease(device, ttl_ms: 7_200_000)
    {token, expiry} = FrpsToken.credential_for_heartbeat(device)
    assert {:ok, %{"expires_at_ms" => ^expiry}} = FrpsToken.verify(token)
    assert expiry > now
    assert expiry <= now + 3_900_000 + 1000
  end

  test "Login and NewProxy reject a deleted device", context do
    :ok = Domain.destroy_device(context.device)
    assert %{"reject" => true} = json_response(login(context.device_name, context.token), 200)
    assert %{"reject" => true} = json_response(http_proxy(context, context.device_name), 200)
  end

  test "a device can register only HTTP proxies in its own subdomain namespace", context do
    raw_name = context.device_name <> "-console"
    assert %{"reject" => false, "unchange" => true} = json_response(http_proxy(context, raw_name), 200)
    assert %{"reject" => true} = json_response(http_proxy(context, FrpsToken.device_name(Ecto.UUID.generate())), 200)
  end

  test "only the exact authenticated user prefix is accepted", context do
    raw_name = context.device_name <> "-console"

    for wire_name <- ["other." <> raw_name, context.device_name <> ".other." <> raw_name] do
      assert %{"reject" => true} = json_response(http_proxy(context, raw_name, wire_name), 200)
    end
  end

  test "tcpmux routes must use the raw device-owned name as their only domain", context do
    raw_name = context.device_name <> "-ssh"

    content = %{
      "user" => %{"user" => context.device_name, "metas" => %{"nixstasis_token" => context.token}},
      "proxy_name" => context.device_name <> "." <> raw_name,
      "proxy_type" => "tcpmux",
      "multiplexer" => "httpconnect",
      "custom_domains" => [raw_name],
      "subdomain" => ""
    }

    allowed = post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{"content" => content})
    assert %{"reject" => false} = json_response(allowed, 200)

    rejected =
      post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{
        "content" => Map.put(content, "custom_domains", [FrpsToken.device_name(Ecto.UUID.generate()) <> "-ssh"])
      })

    assert %{"reject" => true} = json_response(rejected, 200)
  end

  defp login(device_name, token) do
    post(build_conn(), "/internal/frp/authorize?op=Login", %{
      "content" => %{"user" => device_name, "metas" => %{"nixstasis_token" => token}}
    })
  end

  defp http_proxy(context, raw_name, wire_name \\ nil) do
    post(build_conn(), "/internal/frp/authorize?op=NewProxy", %{
      "content" => %{
        "user" => %{"user" => context.device_name, "metas" => %{"nixstasis_token" => context.token}},
        "proxy_name" => wire_name || context.device_name <> "." <> raw_name,
        "proxy_type" => "http",
        "subdomain" => raw_name,
        "custom_domains" => []
      }
    })
  end
end
