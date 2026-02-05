defmodule NixstasisWeb.TerminalChannel do
  use NixstasisWeb, :channel
  require Logger

  # 60 minutes hard limit
  @max_session_duration 60 * 60 * 1000
  # 10 minutes idle timeout
  @idle_timeout 10 * 60 * 1000
  # Warn 30 seconds before idle timeout
  @idle_warning_offset 30 * 1000
  # Time until warning: 9m 30s
  @idle_warning_time @idle_timeout - @idle_warning_offset

  # Join "terminal:DEVICE_ID"
  @impl true
  def join("terminal:" <> device_id, payload, socket) do
    # Verify token
    token = payload["token"]

    case Phoenix.Token.verify(NixstasisWeb.Endpoint, "ssh_private_key", token, max_age: 3600) do
      {:ok, private_key} ->
        device = Nixstasis.Devices.get_device!(device_id)

        # Start the SSH client process for this session
        {:ok, pid} =
          Nixstasis.Devices.SshClient.start_link(
            device_mac: device.mac_address,
            private_key: private_key,
            channel_pid: self()
          )

        Logger.info(
          "Client joined terminal for device #{device_id} with SSH Client #{inspect(pid)}"
        )

        # Schedule session limits
        Process.send_after(self(), :max_duration_reached, @max_session_duration)
        idle_timer = Process.send_after(self(), :idle_warning, @idle_warning_time)

        socket =
          socket
          |> assign(:ssh_client, pid)
          |> assign(:idle_timer, idle_timer)

        {:ok, socket}

      {:error, _reason} ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  # Handle input from the browser terminal
  @impl true
  def handle_in("input", %{"data" => data}, socket) do
    if pid = socket.assigns[:ssh_client] do
      Nixstasis.Devices.SshClient.send_data(pid, data)
    end

    # Reset idle timer
    if timer = socket.assigns[:idle_timer] do
      Process.cancel_timer(timer)
    end

    idle_timer = Process.send_after(self(), :idle_warning, @idle_warning_time)

    {:noreply, assign(socket, :idle_timer, idle_timer)}
  end

  # Session management callbacks
  @impl true
  def handle_info(:max_duration_reached, socket) do
    push(socket, "output", %{data: "\r\n[Session time limit reached (60m). Disconnecting...]\r\n"})

    {:stop, :normal, socket}
  end

  @impl true
  def handle_info(:idle_warning, socket) do
    # Push warning to client
    push(socket, "session_warning", %{
      message: "Session idle. Disconnecting in 30 seconds. Press any key to stay connected."
    })

    push(socket, "output", %{data: "\r\n[Session idle. Disconnecting in 30s...]\r\n"})

    # Schedule actual disconnect
    disconnect_timer = Process.send_after(self(), :idle_timeout, @idle_warning_offset)

    # We update the idle_timer to the disconnect timer so input can cancel it too if needed
    # (though standard input handler resets to full duration)
    {:noreply, assign(socket, :idle_timer, disconnect_timer)}
  end

  @impl true
  def handle_info(:idle_timeout, socket) do
    push(socket, "output", %{data: "\r\n[Session timed out due to inactivity.]\r\n"})
    {:stop, :normal, socket}
  end

  # Handle output from the SSH Client process
  @impl true
  def handle_info({:ssh_output, data}, socket) do
    push(socket, "output", %{data: data})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ssh_exit, status}, socket) do
    push(socket, "output", %{data: "\r\n[Session ended with status: #{status}]\r\n"})
    {:stop, :normal, socket}
  end
end
