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
      assert URI.parse(target.request_url).host == address |> :inet.ntoa() |> List.to_string()
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
          "3fff:1000::1",
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

  test "rejects unresolvable webhook hosts" do
    resolver = fn _host -> {:error, :nxdomain} end

    assert {:error, :nxdomain} =
             Webhook.validate_url("https://missing.example.test/alerts", resolver)
  end
end
