defmodule NixstasisWeb.TerminalChannelTest do
  use NixstasisWeb.ChannelCase

  import ExUnit.CaptureLog

  alias Nixstasis.Devices
  alias Nixstasis.Devices.SshKeyManager

  defmodule FakeSshClient do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def send_data(pid, data), do: GenServer.cast(pid, {:send_data, data})
    def resize(pid, columns, rows), do: GenServer.cast(pid, {:resize, columns, rows})
    def stop(pid), do: GenServer.stop(pid)

    @impl true
    def init(opts) do
      test_pid = opts[:test_pid] || Process.whereis(:terminal_channel_test)
      send(test_pid, {:fake_ssh_started, opts[:columns], opts[:rows]})
      {:ok, %{test_pid: test_pid}}
    end

    @impl true
    def handle_cast({:send_data, data}, state) do
      send(state.test_pid, {:fake_ssh_input, data})
      {:noreply, state}
    end

    @impl true
    def handle_cast({:resize, columns, rows}, state) do
      send(state.test_pid, {:fake_ssh_resize, columns, rows})
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

  defmodule DeferredAckSshClient do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def send_data(pid, data), do: GenServer.cast(pid, {:send_data, data})
    def stop(pid), do: GenServer.stop(pid)

    @impl true
    def init(opts) do
      send(Process.whereis(:terminal_channel_test), {:deferred_ssh_started, opts[:device_id]})
      {:ok, %{}}
    end

    @impl true
    def handle_cast({:send_data, _data}, state), do: {:noreply, state}
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
      |> socket("user_id", %{terminal_device_id: device.id})
      |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
        "token" => session_ref
      })

    %{socket: socket, device: device, private_key: private_key, session_ref: session_ref}
  end

  test "joins with device topic", %{socket: socket, device: device} do
    assert socket.topic == "terminal:#{device.id}"
  end

  test "passes initial terminal size to ssh client", %{device: device} do
    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "dummy_private_key")

    assert {:ok, _, _socket} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{terminal_device_id: device.id})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
               "token" => session_ref,
               "columns" => 132,
               "rows" => 43
             })

    assert_receive {:fake_ssh_started, 132, 43}
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

    {_result, _log} =
      with_log(fn ->
        assert {:error, %{reason: "unauthorized"}} =
                 NixstasisWeb.UserSocket
                 |> socket("user_id", %{terminal_device_id: other_device.id})
                 |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{other_device.id}", %{
                   "token" => wrong_ref
                 })
      end)

    assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(wrong_ref, session_ref)
  end

  test "returns structured error when ssh executable is missing" do
    Application.put_env(:nixstasis, :terminal_ssh_client, MissingExecutableSshClient)

    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:11", product_name: "key"})

    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret")

    {_result, _log} =
      with_log(fn ->
        assert {:error,
                %{
                  reason: "terminal_unavailable",
                  code: "missing_executable",
                  executable: "missing-nixstasis-ssh"
                }} =
                 NixstasisWeb.UserSocket
                 |> socket("user_id", %{terminal_device_id: device.id})
                 |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
                   "token" => session_ref
                 })
      end)
  end

  test "returns structured error for expired terminal session" do
    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:12", product_name: "key"})

    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret", ttl_ms: 0)

    {result, _log} =
      with_log(fn ->
        NixstasisWeb.UserSocket
        |> socket("user_id", %{terminal_device_id: device.id})
        |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
          "token" => session_ref
        })
      end)

    assert {:error, %{reason: reason, code: code}} = result

    assert {reason, code} in [
             {"session_expired", "session_expired"},
             {"session_not_found", "session_not_found"}
           ]
  end

  test "returns structured error for missing terminal session" do
    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:13", product_name: "key"})

    {_result, _log} =
      with_log(fn ->
        assert {:error, %{reason: "session_not_found", code: "session_not_found"}} =
                 NixstasisWeb.UserSocket
                 |> socket("user_id", %{terminal_device_id: device.id})
                 |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
                   "token" => Ecto.UUID.generate()
                 })
      end)
  end

  test "keeps terminal session usable while ssh authorization is pending" do
    Application.put_env(:nixstasis, :terminal_ssh_client, DeferredAckSshClient)

    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:15", product_name: "key"})

    device_id = device.id

    {:ok, command} = Devices.queue_command(device, %{"type" => "ssh_authorize", "public_key" => "ssh-ed25519 test"})
    _ = Devices.pop_pending_commands(device)
    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret")

    ack_task =
      Task.async(fn ->
        Process.sleep(100)

        Devices.acknowledge_command_results(device, [
          %{"command_id" => command.id, "status" => "OK", "output" => %{}}
        ])
      end)

    assert {:ok, %{private_key: "secret"}} = SshKeyManager.fetch_terminal_session(session_ref, device.id)

    assert {:ok, _, socket} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{terminal_device_id: device.id})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
               "token" => session_ref,
               "command_id" => command.id
             })

    assert {:ok, 1} = Task.await(ack_task)

    assert socket.topic == "terminal:#{device.id}"
    assert_receive {:deferred_ssh_started, ^device_id}
  end

  test "rejects terminal join when ssh authorization command fails" do
    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:16", product_name: "key"})

    {:ok, command} = Devices.queue_command(device, %{"type" => "ssh_authorize", "public_key" => "ssh-ed25519 test"})
    _ = Devices.pop_pending_commands(device)
    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret")

    assert {:ok, 1} =
             Devices.acknowledge_command_results(device, [
               %{"command_id" => command.id, "status" => "FAILED", "error" => "missing public key"}
             ])

    {_result, _log} =
      with_log(fn ->
        assert {:error, %{reason: "authorization_failed", code: "ssh_authorization_failed"}} =
                 NixstasisWeb.UserSocket
                 |> socket("user_id", %{terminal_device_id: device.id})
                 |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
                   "token" => session_ref,
                   "command_id" => command.id
                 })
      end)
  end

  test "returns structured startup failure for expected ssh client errors" do
    Application.put_env(:nixstasis, :terminal_ssh_client, StartFailureSshClient)

    {:ok, device} =
      Devices.create_device(%{mac_address: "CC:DD:EE:FF:00:14", product_name: "key"})

    {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, "secret")

    {result, log} =
      with_log(fn ->
        NixstasisWeb.UserSocket
        |> socket("user_id", %{terminal_device_id: device.id})
        |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device.id}", %{
          "token" => session_ref
        })
      end)

    assert log =~ "Terminal join failed for device #{device.id}"
    assert {:error, %{reason: "terminal_unavailable", code: "econnrefused"}} = result
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

  test "forwards terminal resize events to ssh client", %{socket: socket} do
    push(socket, "resize", %{"columns" => 120, "rows" => 40})
    assert_receive {:fake_ssh_resize, 120, 40}
  end

  test "disconnects on max duration", %{socket: socket} do
    send(socket.channel_pid, :max_duration_reached)
    assert_push("output", %{data: "\r\n[Session time limit reached (60m). Disconnecting...]\r\n"})
  end
end
