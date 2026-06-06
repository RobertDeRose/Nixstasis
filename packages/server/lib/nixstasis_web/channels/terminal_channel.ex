defmodule NixstasisWeb.TerminalChannel do
  @moduledoc """
  Channel for browser-based SSH terminal sessions.
  """

  use NixstasisWeb, :channel
  require Logger

  alias Nixstasis.Devices
  alias Nixstasis.Devices.SshKeyManager

  # 60 minutes hard limit
  @max_session_duration 60 * 60 * 1000
  # 10 minutes idle timeout
  @idle_timeout 10 * 60 * 1000
  # Warn 30 seconds before idle timeout
  @idle_warning_offset 30 * 1000
  # Time until warning: 9m 30s
  @idle_warning_time @idle_timeout - @idle_warning_offset
  @ssh_authorization_wait_attempts 30
  @ssh_authorization_wait_interval_ms 500

  # Join "terminal:DEVICE_ID"
  @impl true
  def join("terminal:" <> device_id, payload, socket) do
    session_ref = payload["token"]
    command_id = payload["command_id"]
    columns = parse_terminal_dimension(payload["columns"], 80)
    rows = parse_terminal_dimension(payload["rows"], 24)

    with {:ok, %{private_key: private_key}} <-
           SshKeyManager.fetch_terminal_session(session_ref, device_id),
         :ok <- authorize_terminal_join(socket, device_id),
         :ok <- ensure_ssh_authorized(device_id, command_id),
         {:ok, device} <- get_device(device_id),
         {:ok, pid} <- start_ssh_client(device, private_key, columns, rows) do
      SshKeyManager.clear_terminal_session(session_ref)

      Logger.info("Client joined terminal for device #{device_id} with SSH Client #{inspect(pid)}")

      Process.send_after(self(), :max_duration_reached, @max_session_duration)
      idle_timer = schedule_idle_warning(0)

      socket =
        socket
        |> assign(:terminal_device_id, device_id)
        |> assign(:terminal_session_ref, session_ref)
        |> assign(:ssh_client, pid)
        |> assign(:ssh_client_module, ssh_client_module())
        |> assign(:idle_timer, idle_timer)
        |> assign(:idle_generation, 0)

      {:ok, socket}
    else
      {:error, reason} ->
        maybe_clear_terminal_session(session_ref, reason)
        queue_revoke(device_id, session_ref)
        Logger.warning("Terminal join failed for device #{device_id}: #{inspect(reason)}")
        {:error, terminal_join_error(reason)}
    end
  end

  defp maybe_clear_terminal_session(_session_ref, :ssh_authorization_pending), do: :ok
  defp maybe_clear_terminal_session(session_ref, _reason), do: SshKeyManager.clear_terminal_session(session_ref)

  defp authorize_terminal_join(socket, device_id) do
    terminal_device_id = socket.assigns[:terminal_device_id]

    cond do
      is_nil(terminal_device_id) -> {:error, :unauthorized}
      terminal_device_id == device_id -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp ensure_ssh_authorized(_device_id, nil), do: :ok
  defp ensure_ssh_authorized(_device_id, ""), do: :ok

  defp ensure_ssh_authorized(device_id, command_id) do
    wait_until_ssh_authorized(device_id, command_id, @ssh_authorization_wait_attempts)
  end

  defp wait_until_ssh_authorized(device_id, command_id, attempts) when attempts > 0 do
    case Devices.command_result_status(device_id, command_id) do
      :ok ->
        :ok

      :failed ->
        {:error, :ssh_authorization_failed}

      :pending ->
        Process.sleep(@ssh_authorization_wait_interval_ms)
        wait_until_ssh_authorized(device_id, command_id, attempts - 1)
    end
  end

  defp wait_until_ssh_authorized(_device_id, _command_id, 0), do: {:error, :ssh_authorization_pending}

  # Handle input from the browser terminal
  @impl true
  def handle_in("input", %{"data" => data}, socket) do
    if pid = socket.assigns[:ssh_client] do
      socket.assigns.ssh_client_module.send_data(pid, data)
    end

    if timer = socket.assigns[:idle_timer] do
      Process.cancel_timer(timer)
    end

    idle_generation = socket.assigns[:idle_generation] + 1
    idle_timer = schedule_idle_warning(idle_generation)

    {:noreply,
     socket
     |> assign(:idle_timer, idle_timer)
     |> assign(:idle_generation, idle_generation)}
  end

  @impl true
  def handle_in("resize", %{"columns" => columns, "rows" => rows}, socket) do
    columns = parse_terminal_dimension(columns, nil)
    rows = parse_terminal_dimension(rows, nil)

    if columns && rows do
      if pid = socket.assigns[:ssh_client] do
        resize_ssh_client(socket.assigns.ssh_client_module, pid, columns, rows)
      end
    end

    {:noreply, socket}
  end

  # Session management callbacks
  @impl true
  def handle_info(:max_duration_reached, socket) do
    push(socket, "output", %{data: "\r\n[Session time limit reached (60m). Disconnecting...]\r\n"})

    {:stop, :normal, socket}
  end

  @impl true
  def handle_info({:idle_warning, generation}, socket) do
    if socket.assigns[:idle_generation] == generation do
      push(socket, "session_warning", %{
        message: "Session idle. Disconnecting in 30 seconds. Press any key to stay connected."
      })

      push(socket, "output", %{data: "\r\n[Session idle. Disconnecting in 30s...]\r\n"})

      disconnect_timer =
        Process.send_after(self(), {:idle_timeout, generation}, @idle_warning_offset)

      {:noreply, assign(socket, :idle_timer, disconnect_timer)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:idle_timeout, generation}, socket) do
    if socket.assigns[:idle_generation] == generation do
      push(socket, "output", %{data: "\r\n[Session timed out due to inactivity.]\r\n"})
      {:stop, :normal, socket}
    else
      {:noreply, socket}
    end
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

  @impl true
  def terminate(_reason, socket) do
    session_ref = socket.assigns[:terminal_session_ref]
    SshKeyManager.clear_terminal_session(session_ref)
    queue_revoke(socket.assigns[:terminal_device_id], session_ref)
    stop_ssh_client(socket.assigns[:ssh_client_module], socket.assigns[:ssh_client])
    :ok
  end

  defp get_device(device_id) do
    {:ok, Devices.get_device!(device_id)}
  rescue
    _ -> {:error, :device_not_found}
  end

  defp start_ssh_client(device, private_key, columns, rows) do
    case ssh_client_module().start_link(
           device_id: device.id,
           private_key: private_key,
           channel_pid: self(),
           columns: columns,
           rows: rows
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp terminal_join_error(%{reason: :missing_executable, executable: executable}) do
    %{
      reason: "terminal_unavailable",
      code: "missing_executable",
      executable: executable
    }
  end

  defp terminal_join_error(:expired), do: %{reason: "session_expired", code: "session_expired"}

  defp terminal_join_error(:not_found), do: %{reason: "session_not_found", code: "session_not_found"}

  defp terminal_join_error(:device_not_found), do: %{reason: "device_unavailable", code: "device_not_found"}

  defp terminal_join_error(:device_mismatch), do: %{reason: "unauthorized", code: "device_mismatch"}

  defp terminal_join_error(:unauthorized), do: %{reason: "unauthorized", code: "unauthorized"}

  defp terminal_join_error(:ssh_authorization_pending),
    do: %{reason: "authorization_pending", code: "ssh_authorization_pending"}

  defp terminal_join_error(:ssh_authorization_failed),
    do: %{reason: "authorization_failed", code: "ssh_authorization_failed"}

  defp terminal_join_error(reason) when is_atom(reason) do
    %{reason: "terminal_unavailable", code: Atom.to_string(reason)}
  end

  defp terminal_join_error(_reason), do: %{reason: "terminal_unavailable", code: "startup_failed"}

  defp ssh_client_module do
    Application.get_env(:nixstasis, :terminal_ssh_client, Nixstasis.Devices.SshClient)
  end

  defp schedule_idle_warning(generation) do
    Process.send_after(self(), {:idle_warning, generation}, @idle_warning_time)
  end

  defp stop_ssh_client(_module, nil), do: :ok

  defp stop_ssh_client(module, pid) do
    cond do
      function_exported?(module, :stop, 1) ->
        module.stop(pid)

      Process.alive?(pid) ->
        Process.exit(pid, :shutdown)

      true ->
        :ok
    end
  catch
    _, _ -> :ok
  end

<<<<<<< HEAD
  defp resize_ssh_client(module, pid, columns, rows) do
    if function_exported?(module, :resize, 3) do
      module.resize(pid, columns, rows)
    end
  catch
    _, _ -> :ok
  end

  defp parse_terminal_dimension(value, _default) when is_integer(value) and value > 0, do: value

  defp parse_terminal_dimension(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> default
    end
  end

  defp parse_terminal_dimension(_value, default), do: default

  defp queue_revoke(nil, _session_ref), do: :ok
  defp queue_revoke(_device_id, nil), do: :ok
  defp queue_revoke(_device_id, ""), do: :ok

  defp queue_revoke(device_id, session_ref) do
    case get_device(device_id) do
      {:ok, device} -> _ = Devices.queue_terminal_revoke(device, session_ref)
      _ -> :ok
    end
  end
end
end
