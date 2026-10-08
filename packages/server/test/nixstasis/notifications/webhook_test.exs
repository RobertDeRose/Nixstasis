defmodule Nixstasis.Notifications.WebhookTest do
  use ExUnit.Case, async: false

  alias Nixstasis.Notifications.Webhook

  test "system DNS lookups use a five-second timeout for each address family" do
    # Trace only this lookup task in an isolated session, without mocking :inet
    # or changing resolver settings for other tests. localhost needs no external DNS.
    session = :trace.session_create(:webhook_dns_timeout, self(), [])

    try do
      :trace.function(session, {:inet, :getaddrs, 3}, true, [:local])

      lookup =
        Task.async(fn ->
          receive do
            :resolve -> Webhook.validate_url("https://localhost/alerts")
          end
        end)

      :trace.process(session, lookup.pid, true, [:call])
      send(lookup.pid, :resolve)
      assert Task.await(lookup) == {:error, :non_public_address}
      pid = lookup.pid

      assert_receive {:trace, ^pid, :call, {:inet, :getaddrs, [~c"localhost", :inet, 5_000]}}, 1_000
      assert_receive {:trace, ^pid, :call, {:inet, :getaddrs, [~c"localhost", :inet6, 5_000]}}, 1_000
    after
      :trace.session_destroy(session)
    end
  end

  test "preserves the original authority when DNS resolves to IPv4 or IPv6" do
    for address <- [{93, 184, 216, 34}, {0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}],
        {port, expected_host} <- [
          {"", "hooks.example.test"},
          {":443", "hooks.example.test"},
          {":8443", "hooks.example.test:8443"}
        ] do
      resolver = fn "hooks.example.test" -> {:ok, [address]} end

      assert {:ok, target} =
               Webhook.validate_url("https://user:secret@hooks.example.test#{port}/alerts?token=secret", resolver)

      assert target.host_header == expected_host
      assert target.hostname == "hooks.example.test"
      pinned = URI.parse(target.request_url)
      assert pinned.host == address |> :inet.ntoa() |> List.to_string()
      assert pinned.port == if(port == ":8443", do: 8443, else: 443)
      assert pinned.path == "/alerts"
      assert pinned.query == "token=secret"
      assert pinned.userinfo == "user:secret"
    end
  end

  test "delivery preserves Host and port through Finch request construction" do
    previous = Req.default_options()
    on_exit(fn -> Req.default_options(previous) end)

    Req.default_options(
      finch_request: fn request, finch_request, _name, _options ->
        send(self(), {:webhook_request, request, finch_request})
        {request, Req.Response.new(status: 200)}
      end
    )

    alert = %{id: "alert-id", type: :offline, message: "Offline", triggered_at: nil}

    for host <- ["93.184.216.34", "[2606:4700::1111]"],
        port <- ["", ":8443"] do
      assert {:ok, %Req.Response{status: 200}} =
               Webhook.send_alert_webhook("https://#{host}#{port}/alerts", alert)

      assert_receive {:webhook_request, request, finch_request}
      assert {"host", host <> port} in finch_request.headers
      assert request.options[:connect_options][:hostname] == String.trim(host, "[") |> String.trim_trailing("]")
      expected_transport = if String.starts_with?(host, "["), do: [inet6: true], else: nil
      assert request.options[:connect_options][:transport_opts] == expected_transport
      assert request.options[:redirect] == false
      assert request.options[:retry] == false
    end
  end

  test "accepts HTTPS destinations only when every resolved address is public" do
    resolver = fn "hooks.example.test" -> {:ok, [{93, 184, 216, 34}]} end

    assert {:ok, target} =
             Webhook.validate_url("https://hooks.example.test/alerts?token=secret", resolver)

    assert target.hostname == "hooks.example.test"
    assert target.address == {93, 184, 216, 34}
    assert target.request_url == "https://93.184.216.34/alerts?token=secret"
  end

  test "rejects cleartext webhook URLs" do
    resolver = fn _host -> {:ok, [{93, 184, 216, 34}]} end

    assert {:error, :https_required} =
             Webhook.validate_url("http://hooks.example.test/alerts", resolver)
  end

  test "delivery rejects a private target before issuing a request" do
    assert {:error, :non_public_address} = Webhook.send_alert_webhook("https://127.0.0.1/alerts", nil)
  end

  test "rejects loopback and private literal addresses" do
    assert {:error, :non_public_address} = Webhook.validate_url("https://127.0.0.1/alerts")
    assert {:error, :non_public_address} = Webhook.validate_url("https://10.1.2.3/alerts")
    assert {:error, :non_public_address} = Webhook.validate_url("https://169.254.169.254/latest/meta-data")
    assert {:error, :non_public_address} = Webhook.validate_url("https://[::1]/alerts")
  end

  test "rejects a hostname when any DNS answer is private" do
    resolver = fn "mixed.example.test" ->
      {:ok, [{93, 184, 216, 34}, {10, 0, 0, 5}]}
    end

    assert {:error, :non_public_address} =
             Webhook.validate_url("https://mixed.example.test/alerts", resolver)
  end

  test "rejects non-global IPv6 literals and mixed DNS answers" do
    for host <- [
          "::",
          "::1",
          "::2",
          "::ffff:127.0.0.1",
          "64:ff9b::1",
          "64:ff9b:1::1",
          "100::1",
          "100:0:0:1::1",
          "2001::1",
          "2001:1::4",
          "2001:2::1",
          "2001:4:111::1",
          "2001:10::1",
          "2001:1f:ffff:ffff:ffff:ffff:ffff:ffff",
          "2001:20::1",
          "2001:30::1",
          "2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff",
          "2001:db8::1",
          "2002::1",
          "3ffe::",
          "3ffe:831f::1",
          "3ffe:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
          "3fff:1000::1",
          "3fff::1",
          "3fff:fff:ffff:ffff:ffff:ffff:ffff:ffff",
          "4000::1",
          "5f00::1",
          "fc00::1",
          "fe80::1",
          "fec0::1",
          "ff00::1"
        ] do
      assert {:error, :non_public_address} = Webhook.validate_url("https://[#{host}]/alerts")
      assert {:error, :non_public_address} = Webhook.send_alert_webhook("https://[#{host}]/alerts", nil)
      {:ok, address} = :inet.parse_address(String.to_charlist(host))

      for addresses <- [[{93, 184, 216, 34}, address], [address, {93, 184, 216, 34}]] do
        resolver = fn "mixed.example.test" -> {:ok, addresses} end
        assert {:error, :non_public_address} = Webhook.validate_url("https://mixed.example.test/alerts", resolver)
      end
    end
  end

  test "preserves public IPv6 ranges and globally routable protocol services" do
    for host <- [
          "2001:1::1",
          "2001:1::2",
          "2001:1::3",
          "2001:3::1",
          "2001:3:ffff:ffff:ffff:ffff:ffff:ffff",
          "2001:4:112::1",
          "2001:4:112:ffff:ffff:ffff:ffff:ffff",
          "2001:200::1",
          "2001:db7::1",
          "2001:db9::1",
          "2001:4860:4860::8888",
          "2003::1",
          "2606:4700::1111",
          "2620:4f:8000::1",
          "::ffff:93.184.216.34"
        ] do
      assert {:ok, target} = Webhook.validate_url("https://[#{host}]/alerts")
      {:ok, address} = :inet.parse_address(String.to_charlist(host))
      assert target.address == address
      resolver = fn "hooks.example.test" -> {:ok, [address]} end
      assert {:ok, resolved_target} = Webhook.validate_url("https://hooks.example.test/alerts", resolver)
      assert resolved_target.address == address
    end
  end

  test "only accepts allocated IPv6 global unicast ranges" do
    # IANA Global Unicast registry, 2025-10-10: endpoint pairs include merged
    # adjacent allocations. Keep separate from the classifier's numeric table.
    ranges = [
      {"2001:200::", "2001:fff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2001:1200::", "2001:4dff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2001:5000::", "2001:5fff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2001:8000::", "2001:bfff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2003::", "2003:3fff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2400::", "241f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2600::", "260f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2610::", "2610:1ff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2620::", "2620:1ff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2630::", "263f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2800::", "280f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2a00::", "2a1f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"},
      {"2c00::", "2c0f:ffff:ffff:ffff:ffff:ffff:ffff:ffff"}
    ]

    for {first, last} <- ranges, host <- [first, last] do
      assert {:ok, _} = Webhook.validate_url("https://[#{host}]/alerts")
    end

    for host <- [
          "2000::1",
          "2001:1000::1",
          "2001:4e00::1",
          "2001:6000::1",
          "2001:c000::1",
          "2003:4000::1",
          "2004::1",
          "2420::1",
          "2610:200::1",
          "2611::1",
          "2620:200::1",
          "2621::1",
          "2640::1",
          "2810::1",
          "2a20::1",
          "2c10::1",
          "2d00::1",
          "2e00::1",
          "3000::1",
          "3ffd::1",
          "3fff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"
        ] do
      assert {:error, :non_public_address} = Webhook.validate_url("https://[#{host}]/alerts")
      {:ok, address} = :inet.parse_address(String.to_charlist(host))

      for addresses <- [[{0x2606, 0x4700, 0, 0, 0, 0, 0, 0x1111}, address], [address, {93, 184, 216, 34}]] do
        resolver = fn _ -> {:ok, addresses} end
        assert {:error, :non_public_address} = Webhook.validate_url("https://hooks.example.test", resolver)
      end
    end
  end

  test "mapped IPv6 applies the embedded IPv4 boundary in both notations" do
    for ipv4 <- [
          "0.0.0.0",
          "10.0.0.1",
          "100.64.0.1",
          "127.0.0.1",
          "169.254.169.254",
          "172.16.0.1",
          "192.168.0.1",
          "192.0.2.1",
          "198.18.0.1",
          "224.0.0.1"
        ] do
      {:ok, address} = :inet.parse_address(String.to_charlist("::ffff:" <> ipv4))
      canonical = address |> :inet.ntoa() |> List.to_string()

      for host <- ["::ffff:" <> ipv4, canonical] do
        assert {:error, :non_public_address} = Webhook.validate_url("https://[#{host}]/alerts")
      end
    end
  end

  test "rejects unresolvable webhook hosts" do
    resolver = fn _host -> {:error, :nxdomain} end

    assert {:error, :nxdomain} =
             Webhook.validate_url("https://missing.example.test/alerts", resolver)
  end
end
