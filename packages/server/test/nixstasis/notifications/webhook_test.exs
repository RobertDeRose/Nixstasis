defmodule Nixstasis.Notifications.WebhookTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Notifications.Webhook

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
