defmodule NixstasisWeb.Plugs.RateLimiterTest do
  use NixstasisWeb.ConnCase, async: false

  alias NixstasisWeb.Plugs.RateLimiter
  alias NixstasisWeb.RateLimiterStore

  setup do
    previous = Application.get_env(:nixstasis, :rate_limit)
    RateLimiterStore.clear()

    on_exit(fn ->
      RateLimiterStore.clear()

      if previous do
        Application.put_env(:nixstasis, :rate_limit, previous)
      else
        Application.delete_env(:nixstasis, :rate_limit)
      end
    end)

    :ok
  end

  test "pre-auth limits use finite route buckets instead of attacker device IDs" do
    configure(preauth_limit: 100, preauth_global_limit: 1_000, preauth_max_keys: 8)

    Enum.each(1..50, fn suffix ->
      conn = preauth_request("/api/v1/devices/not-a-uuid-#{suffix}/heartbeat")
      refute conn.halted
    end)

    assert RateLimiterStore.bounded_size() == 1
  end

  test "heartbeat and command-result pre-auth quotas do not collide" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    device_id = Ecto.UUID.generate()

    heartbeat = preauth_request("/api/v1/devices/#{device_id}/heartbeat")
    command_results = preauth_request("/api/v1/devices/#{device_id}/command_results")

    refute heartbeat.halted
    refute command_results.halted

    assert %{"error" => %{"code" => "rate_limited"}} =
             preauth_request("/api/v1/devices/#{device_id}/heartbeat")
             |> json_response(429)
  end

  test "registration uses the trusted Caddy client IP instead of the proxy peer" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    path = "/api/v1/devices/register"

    first = preauth_request(path, {172, 18, 0, 2}, trusted_client_headers("198.51.100.10"))
    second = preauth_request(path, {172, 18, 0, 2}, trusted_client_headers("198.51.100.11"))

    refute first.halted
    refute second.halted

    assert %{"error" => %{"code" => "rate_limited"}} =
             preauth_request(path, {172, 18, 0, 2}, trusted_client_headers("198.51.100.10"))
             |> json_response(429)
  end

  test "direct IPv4-mapped origins share their IPv4 quota, not other mapped origins" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    path = "/api/v1/devices/register"

    refute preauth_request(path, {0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x640A}).halted
    assert preauth_request(path, {198, 51, 100, 10}).status == 429
    refute preauth_request(path, {0, 0, 0, 0, 0, 0xFFFF, 0xC633, 0x640B}).halted
    assert preauth_request(path, {198, 51, 100, 11}).status == 429
    assert RateLimiterStore.bounded_size() == 2
  end

  test "trusted proxy IPv4-mapped origins share their IPv4 quota, not other mapped origins" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    path = "/api/v1/devices/register"
    peer = {172, 18, 0, 2}

    refute preauth_request(path, peer, trusted_client_headers("::ffff:198.51.100.10")).halted
    assert preauth_request(path, peer, trusted_client_headers("198.51.100.10")).status == 429
    refute preauth_request(path, peer, trusted_client_headers("::ffff:c633:640b")).halted
    assert preauth_request(path, peer, trusted_client_headers("198.51.100.11")).status == 429
    assert RateLimiterStore.bounded_size() == 2
  end

  test "direct IPv6 origins share a quota within a /64" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    path = "/api/v1/devices/register"

    refute preauth_request(path, {0x2001, 0xDB8, 1, 2, 0, 0, 0, 1}).halted
    assert preauth_request(path, {0x2001, 0xDB8, 1, 2, 9, 8, 7, 6}).status == 429
    refute preauth_request(path, {0x2001, 0xDB8, 1, 3, 0, 0, 0, 1}).halted
    assert RateLimiterStore.bounded_size() == 2
  end

  test "trusted proxy IPv6 origins share a quota within a /64" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    path = "/api/v1/devices/register"
    peer = {172, 18, 0, 2}

    refute preauth_request(path, peer, trusted_client_headers("2001:db8:1:2::1")).halted
    assert preauth_request(path, peer, trusted_client_headers("2001:db8:1:2:ffff::2")).status == 429
    refute preauth_request(path, peer, trusted_client_headers("2001:db8:1:3::1")).halted
    assert RateLimiterStore.bounded_size() == 2
  end

  test "untrusted callers cannot spoof the internal client IP header" do
    configure(preauth_limit: 1, preauth_global_limit: 100)
    device_id = Ecto.UUID.generate()
    path = "/api/v1/devices/#{device_id}/heartbeat"

    first = preauth_request(path, {203, 0, 113, 9}, [{"x-nixstasis-client-ip", "198.51.100.10"}])
    second = preauth_request(path, {203, 0, 113, 9}, [{"x-nixstasis-client-ip", "198.51.100.11"}])

    refute first.halted
    assert %{"error" => %{"code" => "rate_limited"}} = json_response(second, 429)
  end

  test "global pre-auth quota bounds floods spread across source addresses" do
    configure(preauth_limit: 100, preauth_global_limit: 2)
    device_id = Ecto.UUID.generate()
    path = "/api/v1/devices/#{device_id}/heartbeat"

    refute preauth_request(path, {198, 51, 100, 1}).halted
    refute preauth_request(path, {198, 51, 100, 2}).halted

    assert %{"error" => %{"code" => "rate_limited"}} =
             preauth_request(path, {198, 51, 100, 3})
             |> json_response(429)
  end

  defp configure(values) do
    Application.put_env(:nixstasis, :rate_limit, Keyword.put_new(values, :window_ms, 60_000))
  end

  defp preauth_request(path, remote_ip \\ {127, 0, 0, 1}, headers \\ []) do
    headers
    |> Enum.reduce(%{Plug.Test.conn(:post, path) | remote_ip: remote_ip}, fn {name, value}, conn ->
      Plug.Conn.put_req_header(conn, name, value)
    end)
    |> RateLimiter.call([])
  end

  defp trusted_client_headers(client_ip) do
    [
      {"x-nixstasis-proxy-token", Application.fetch_env!(:nixstasis, :proxy_auth_token)},
      {"x-nixstasis-client-ip", client_ip}
    ]
  end
end
