defmodule Nixstasis.Monitoring.HeartbeatTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring

  @host_key_a "ssh-ed25519 " <> Base.encode64(<<11::32, "ssh-ed25519", 32::32, 0::256>>)
  @host_key_b "ssh-ed25519 " <> Base.encode64(<<11::32, "ssh-ed25519", 32::32, 1::256>>)

  test "a competing host-key trust decision does not interrupt a heartbeat" do
    {:ok, device} = Devices.create_device(%{mac_address: "10:00:00:00:00:04", product_name: "P1"})
    {:ok, enrolled} = Devices.record_ssh_host_key(device, @host_key_a)
    {:ok, changed} = Devices.record_ssh_host_key(enrolled, @host_key_b)
    {:ok, command} = Devices.queue_command(changed, %{"cmd" => "update"})

    handler_id = {__MODULE__, self()}

    # Simulate the operator accepting the key after the last-seen UPDATE has
    # produced its result, but before the heartbeat records its SSH host key.
    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :repo, :query],
        &__MODULE__.accept_host_key_after_last_seen/4,
        %{handler_id: handler_id, test_pid: self(), device: changed}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, updated, [delivered]} =
             Monitoring.heartbeat(changed, %{"ssh_host_key" => @host_key_a, "telemetry" => %{"temperature" => 21}})

    assert_received {:operator_trust_result, {:ok, trusted}}
    assert trusted.ssh_host_key == @host_key_b
    assert delivered.id == command.id
    refute is_nil(updated.last_seen_at)
    assert [%{payload: %{"temperature" => 21}}] = Domain.list_telemetry_events!()

    current = Devices.get_device!(device.id)
    assert current.ssh_host_key == @host_key_b
    assert current.ssh_host_key_trusted_by == "operator:test"
    assert is_nil(current.ssh_host_key_pending)
  end

  @doc false
  def accept_host_key_after_last_seen(_event, _measurements, metadata, config) do
    if self() == config.test_pid and String.starts_with?(metadata.query, "UPDATE \"devices\"") and
         String.contains?(metadata.query, "\"last_seen_at\" =") do
      :telemetry.detach(config.handler_id)

      result =
        Devices.accept_pending_ssh_host_key(
          config.device,
          "operator:test",
          Devices.ssh_host_key_fingerprint(@host_key_b)
        )

      send(config.test_pid, {:operator_trust_result, result})
    end
  end
end
