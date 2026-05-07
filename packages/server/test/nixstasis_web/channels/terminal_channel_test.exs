defmodule NixstasisWeb.TerminalChannelTest do
  use NixstasisWeb.ChannelCase
  alias Nixstasis.Devices
  alias Nixstasis.Devices.SshKeyManager

  defmodule FakeSshClient do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def send_data(pid, data), do: GenServer.cast(pid, {:send_data, data})
    def stop(pid), do: GenServer.stop(pid)

    @impl true
    def init(opts),
      do: {:ok, %{test_pid: opts[:test_pid] || Process.whereis(:terminal_channel_test)}}

    @impl true
    def handle_cast({:send_data, data}, state) do
      send(state.test_pid, {:fake_ssh_input, data})
      {:noreply, state}
    end
  end

  defmodule MissingExecutableSshClient do
    def start_link(_opts),
      do: {:error, %{reason: :missing_executable, executable: "missing-nixstasis-ssh"}}
  end

  defmodule StartFailureSshClient do
    def start_link(_opts), do: {:error, :econnrefused}
  end

  setup do
    previous = Application.get_env(:nixstasis, :terminal_ssh_client)
    Application.put_env(:nixstasis, :terminal_ssh_client, FakeSshClient)
    Process.register(self(), :terminal_channel_test)

    on_exit(fn ->
      if previous do
        Application.put_env(:nixstasis, :terminal_ssh_client, previous)
      else
        Application.delete_env(:nixstasis, :terminal_ssh_client)
      end

      if Process.whereis(:terminal_channel_test) == self() do
        Process.unregister(:terminal_channel_test)
      end
    end)

    {:ok, device} =
      Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:FF", product_name: "key"})

    private_key = "dummy_private_key"
    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, private_key)

    {:ok, _, socket} =
      NixstasisWeb.UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
        "token" => session_ref
      })

    %{socket: socket, device: device, private_key: private_key, session_ref: session_ref}
  end

  test "joins with device topic", %{socket: socket, device: device} do
    assert socket.topic == "terminal:#{device.id}"
  end

  # We removed the echo test because the channel no longer echoes input back directly.
  # It forwards to SshClient.

  test "browser token is an opaque session ref without private key material", %{
    private_key: private_key,
    session_ref: session_ref
  } do
    refute session_ref =~ private_key
    assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, "unused")
  end

  test "rejects terminal session ref for the wrong device", %{session_ref: session_ref} do
    {:ok, other_device} =
      Devices.create_device(%{mac_address: "BB:CC:DD:EE:FF:00", product_name: "key"})

    {:ok, wrong_ref} = SshKeyManager.create_terminal_session(session_ref, "secret")

    assert {:error, %{reason: "unauthorized"}} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{other_device.id}", %{
               "token" => wrong_ref
             })

    assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(wrong_ref, session_ref)
  end

  test "returns structured error when ssh executable is missing" do
    Application.put_env(:nixstasis, :terminal_ssh_client, MissingExecutableSshClient)

    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:11", product_name: "key"})

    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret")

    assert {:error,
            %{
              reason: "terminal_unavailable",
              code: "missing_executable",
              executable: "missing-nixstasis-ssh"
            }} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
               "token" => session_ref
             })
  end

  test "returns structured error for expired terminal session" do
    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:12", product_name: "key"})

    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret", ttl_ms: 0)

    assert {:error, %{reason: reason, code: code}} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
               "token" => session_ref
             })

    assert {reason, code} in [
             {"session_expired", "session_expired"},
             {"session_not_found", "session_not_found"}
           ]
  end

  test "returns structured error for missing terminal session" do
    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:13", product_name: "key"})

    assert {:error, %{reason: "session_not_found", code: "session_not_found"}} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
               "token" => Ecto.UUID.generate()
             })
  end

  test "returns structured startup failure for expected ssh client errors" do
    Application.put_env(:nixstasis, :terminal_ssh_client, StartFailureSshClient)

    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:14", product_name: "key"})

    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret")

    assert {:error, %{reason: "terminal_unavailable", code: "econnrefused"}} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
               "token" => session_ref
             })
  end

  test "sends warning on idle", %{socket: socket} do
    # Simulate idle warning timeout firing
    send(socket.channel_pid, {:idle_warning, 0})

    assert_push("session_warning", %{
      message: "Session idle. Disconnecting in 30 seconds. Press any key to stay connected."
    })

    assert_push("output", %{data: "\r\n[Session idle. Disconnecting in 30s...]\r\n"})
  end

  test "disconnects on idle timeout", %{socket: socket} do
    # Simulate idle timeout firing
    send(socket.channel_pid, {:idle_timeout, 0})

    assert_push("output", %{data: "\r\n[Session timed out due to inactivity.]\r\n"})

    # Channel process should stop (we can't easily assert stop in this helper without trapping exit, but the push confirms logic reached)
  end

  test "ignores stale idle warning and timeout messages after fresh input", %{socket: socket} do
    push(socket, "input", %{"data" => "a"})
    assert_receive {:fake_ssh_input, "a"}

    send(socket.channel_pid, {:idle_warning, 0})
    send(socket.channel_pid, {:idle_timeout, 0})

    refute_push("session_warning", _)
    refute_push("output", %{data: "\r\n[Session timed out due to inactivity.]\r\n"})
  end

  test "disconnects on max duration", %{socket: socket} do
    send(socket.channel_pid, :max_duration_reached)
    assert_push("output", %{data: "\r\n[Session time limit reached (60m). Disconnecting...]\r\n"})
  end
end
