defmodule Nixstasis.Monitoring.OfflineCheckerTest do
  use Nixstasis.DataCase

  import ExUnit.CaptureLog
  import Swoosh.TestAssertions

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring
  alias Nixstasis.Monitoring.Alert
  alias Nixstasis.Monitoring.OfflineChecker
  alias Nixstasis.Settings
  alias Nixstasis.TestSupport.WebhookCapturePlug

  setup :set_swoosh_global

  test "uses the stored offline window when checking devices" do
    assert {:ok, _setting} = Settings.put_setting("offline_window", %{"minutes" => 20})

    {:ok, device} = Devices.register_device(%{mac_address: "44:44:44:44:44:44", product_name: "P1"})
    {:ok, device} = Devices.approve_device(device)

    {:ok, _device} =
      Devices.update_device(device, %{
        last_seen_at: DateTime.utc_now() |> DateTime.add(-15, :minute)
      })

    {:ok, checker} = GenServer.start_link(OfflineChecker, %{})

    send(checker, :check)
    :sys.get_state(checker)

    assert Repo.all(Alert) == []
  end

  test "active offline alerts resolve when heartbeat resumes" do
    {:ok, device} = Devices.register_device(%{mac_address: "55:55:55:55:55:55", product_name: "P2"})
    {:ok, device} = Devices.approve_device(device)

    {:ok, device} =
      Devices.update_device(device, %{
        last_seen_at: DateTime.utc_now() |> DateTime.add(-20, :minute)
      })

    {result, _log} = with_log(fn -> Monitoring.check_offline_devices(window_minutes: 10) end)

    assert result.status == :success

    [alert] = Repo.all(Alert)
    assert alert.type == :offline
    assert alert.status == :active

    assert {:ok, _device, []} = Monitoring.heartbeat(device, %{"telemetry" => %{}})

    resolved_alert = Domain.list_alerts!() |> Enum.find(&(&1.id == alert.id))
    assert resolved_alert.status == :resolved
    assert resolved_alert.message == "Device heartbeat resumed"
  end

  test "alert creation sends configured email notifications without blocking creation" do
    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "email" => "alerts@example.com",
               "webhook_url" => nil
             })

    {:ok, device} = Devices.register_device(%{mac_address: "66:66:66:66:66:66", product_name: "P3"})
    {:ok, approved_device} = Devices.approve_device(device)

    {:ok, updated_device} =
      Devices.update_device(approved_device, %{
        last_seen_at: DateTime.utc_now() |> DateTime.add(-20, :minute)
      })

    result = Monitoring.check_offline_devices(window_minutes: 10)

    assert result.status == :success
    assert [%Alert{}] = Domain.list_alerts!()

    assert updated_device.id

    assert_receive {:email, email}, 500
    assert [{_, "alerts@example.com"}] = email.to
  end

  test "alert creation sends configured webhook notifications" do
    port = free_port()

    start_supervised!({Bandit, plug: {WebhookCapturePlug, test_pid: self()}, port: port})

    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "email" => nil,
               "webhook_url" => "http://127.0.0.1:#{port}/alerts"
             })

    {:ok, device} = Devices.register_device(%{mac_address: "68:68:68:68:68:68", product_name: "P5"})
    {:ok, approved_device} = Devices.approve_device(device)

    {:ok, _updated_device} =
      Devices.update_device(approved_device, %{
        last_seen_at: DateTime.utc_now() |> DateTime.add(-20, :minute)
      })

    {result, _log} = with_log(fn -> Monitoring.check_offline_devices(window_minutes: 10) end)

    assert result.status == :success

    assert_receive {:webhook_request, "POST", "/alerts", body}, 1_000
    assert body =~ "offline"
  end

  test "notification delivery failures do not break alert creation paths" do
    stub_webhook_notifier(__MODULE__.NoopWebhookNotifier)

    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "webhook_url" => "http://127.0.0.1:1/alerts"
             })

    {:ok, device} = Devices.register_device(%{mac_address: "77:77:77:77:77:77", product_name: "P4"})
    {:ok, approved_device} = Devices.approve_device(device)

    {:ok, _updated_device} =
      Devices.update_device(approved_device, %{
        last_seen_at: DateTime.utc_now() |> DateTime.add(-20, :minute)
      })

    result = Monitoring.check_offline_devices(window_minutes: 10)

    assert result.status == :success
    assert [%Alert{}] = Domain.list_alerts!()
  end

  test "rule-triggered alerts send configured email and webhook notifications" do
    port = free_port()

    start_supervised!({Bandit, plug: {WebhookCapturePlug, test_pid: self()}, port: port})

    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "email" => "alerts@example.com",
               "webhook_url" => "http://127.0.0.1:#{port}/alerts"
             })

    {:ok, _rule} =
      Domain.create_rule(%{
        name: "High temperature",
        product_name: "P6",
        condition_field: "temp",
        operator: ">",
        threshold_value: "75"
      })

    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "88:88:88:88:88:88",
        "product_name" => "P6",
        "schema" => %{
          "product" => "P6",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    {:ok, device} = Devices.approve_device(device)

    assert {:ok, _device, []} = Monitoring.heartbeat(device, %{"telemetry" => %{"temp" => 80}})

    assert [%Alert{type: :threshold}] = Domain.list_alerts!()

    assert_receive {:email, email}, 1_000
    assert [{_, "alerts@example.com"}] = email.to

    assert_receive {:webhook_request, "POST", "/alerts", body}, 1_000
    assert body =~ "threshold"
  end

  test "rule-triggered notification failures do not block alert creation" do
    stub_webhook_notifier(__MODULE__.NoopWebhookNotifier)

    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "webhook_url" => "http://127.0.0.1:1/alerts"
             })

    {:ok, _rule} =
      Domain.create_rule(%{
        name: "Critical temperature",
        product_name: "P7",
        condition_field: "temp",
        operator: ">",
        threshold_value: "90"
      })

    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "99:99:99:99:99:99",
        "product_name" => "P7",
        "schema" => %{
          "product" => "P7",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    {:ok, device} = Devices.approve_device(device)

    result = Monitoring.heartbeat(device, %{"telemetry" => %{"temp" => 95}})

    assert {:ok, _device, []} = result
    assert [%Alert{type: :threshold}] = Domain.list_alerts!()
  end

  defp stub_webhook_notifier(notifier) do
    previous_notifier = Application.get_env(:nixstasis, :webhook_notifier)
    Application.put_env(:nixstasis, :webhook_notifier, notifier)

    on_exit(fn ->
      if is_nil(previous_notifier) do
        Application.delete_env(:nixstasis, :webhook_notifier)
      else
        Application.put_env(:nixstasis, :webhook_notifier, previous_notifier)
      end
    end)
  end

  defmodule NoopWebhookNotifier do
    def send_alert_webhook(_url, _alert), do: :ok
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
