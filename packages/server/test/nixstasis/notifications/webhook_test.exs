defmodule Nixstasis.Notifications.WebhookTest do
  use ExUnit.Case, async: false

  alias Nixstasis.Notifications.Webhook

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

  test "rejects unresolvable webhook hosts" do
    resolver = fn _host -> {:error, :nxdomain} end

    assert {:error, :nxdomain} =
             Webhook.validate_url("https://missing.example.test/alerts", resolver)
  end
end
