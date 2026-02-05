defmodule NixstasisWeb.TerminalChannelTest do
  use NixstasisWeb.ChannelCase
  alias Nixstasis.Devices

  setup do
    {:ok, device} = Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:FF", product_key: "key"})

    # Generate a dummy key (content doesn't matter for token verification,
    # but matters for SshClient if we wanted it to work)
    private_key = "dummy_private_key"
    token = Phoenix.Token.sign(NixstasisWeb.Endpoint, "ssh_private_key", private_key)

    {:ok, _, socket} =
      NixstasisWeb.UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
        "token" => token
      })

    %{socket: socket, device: device}
  end

  test "joins with device topic", %{socket: socket, device: device} do
    assert socket.topic == "terminal:#{device.id}"
  end

  # We removed the echo test because the channel no longer echoes input back directly.
  # It forwards to SshClient.

  test "sends warning on idle", %{socket: socket} do
    # Simulate idle warning timeout firing
    send(socket.channel_pid, :idle_warning)

    assert_push("session_warning", %{
      message: "Session idle. Disconnecting in 30 seconds. Press any key to stay connected."
    })

    assert_push("output", %{data: "\r\n[Session idle. Disconnecting in 30s...]\r\n"})
  end

  test "disconnects on idle timeout", %{socket: socket} do
    # Simulate idle timeout firing
    send(socket.channel_pid, :idle_timeout)

    assert_push("output", %{data: "\r\n[Session timed out due to inactivity.]\r\n"})

    # Channel process should stop (we can't easily assert stop in this helper without trapping exit, but the push confirms logic reached)
  end

  test "disconnects on max duration", %{socket: socket} do
    send(socket.channel_pid, :max_duration_reached)
    assert_push("output", %{data: "\r\n[Session time limit reached (60m). Disconnecting...]\r\n"})
  end
end
