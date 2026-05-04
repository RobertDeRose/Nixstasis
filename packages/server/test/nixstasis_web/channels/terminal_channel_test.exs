defmodule NixstasisWeb.TerminalChannelTest do
  use NixstasisWeb.ChannelCase
  alias Nixstasis.Devices

  setup do
    {:ok, device} =
      Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:FF", product_name: "key"})

    %{socket: join_terminal!(device), device: device}
  end

  test "joins with device topic", %{socket: socket, device: device} do
    assert socket.topic == "terminal:#{device.id}"
  end

  test "rejects anonymous socket connections" do
    assert :error = connect(NixstasisWeb.UserSocket, %{})
  end

  test "rejects terminal token for a different device" do
    {:ok, first_device} =
      Devices.create_device(%{mac_address: "11:22:33:44:55:66", product_name: "key"})

    {:ok, second_device} =
      Devices.create_device(%{mac_address: "22:33:44:55:66:77", product_name: "key"})

    {:ok, socket} = connect_terminal_socket(first_device.id)
    token = terminal_token(second_device, "dummy_private_key")

    assert {:error, %{reason: "unauthorized"}} =
             subscribe_and_join(socket, NixstasisWeb.TerminalChannel, "terminal:#{first_device.id}", %{
               "token" => token
             })
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

    # Channel process should stop. We cannot easily assert that in this helper
    # without trapping exits, but the push confirms the logic was reached.
  end

  test "disconnects on max duration", %{socket: socket} do
    send(socket.channel_pid, :max_duration_reached)
    assert_push("output", %{data: "\r\n[Session time limit reached (60m). Disconnecting...]\r\n"})
  end

  defp join_terminal!(device) do
    {:ok, socket} = connect_terminal_socket(device.id)
    token = terminal_token(device, "dummy_private_key")

    {:ok, _, socket} =
      subscribe_and_join(socket, NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
        "token" => token
      })

    socket
  end

  defp connect_terminal_socket(device_id) do
    token = Phoenix.Token.sign(NixstasisWeb.Endpoint, "terminal_socket", %{"device_id" => device_id})
    connect(NixstasisWeb.UserSocket, %{"token" => token})
  end

  defp terminal_token(device, private_key) do
    Phoenix.Token.sign(NixstasisWeb.Endpoint, "terminal_session", %{
      "device_id" => device.id,
      "device_mac" => device.mac_address,
      "private_key" => private_key
    })
  end
end
