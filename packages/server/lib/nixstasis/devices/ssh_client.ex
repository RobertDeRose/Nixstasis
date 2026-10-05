defmodule Nixstasis.Devices.SshClient do
  @moduledoc """
  SSH client for browser terminal sessions through the FRPS TCP mux endpoint.
  """
  use GenServer
  require Logger

  alias Nixstasis.Devices.SshHostKey

  @max_terminal_dimension 1_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  def resize(pid, columns, rows) do
    GenServer.cast(pid, {:resize, columns, rows})
  end

  def stop(pid) do
    GenServer.stop(pid, :normal, 5_000)
  end

  def validate_executables(opts \\ []) do
    ssh_executable = Keyword.get(opts, :ssh_executable, "ssh")
    proxy_executable = Keyword.get(opts, :proxy_executable, "ncat")
    env_executable = Keyword.get(opts, :env_executable, "env")
    mktemp_executable = Keyword.get(opts, :mktemp_executable, "mktemp")

    with {:ok, ssh_path} <- find_required_executable(ssh_executable),
         {:ok, proxy_path} <- find_required_executable(proxy_executable),
         {:ok, env_path} <- find_required_executable(env_executable),
         {:ok, mktemp_path} <- find_required_executable(mktemp_executable) do
      {:ok, %{ssh: ssh_path, proxy: proxy_path, env: env_path, mktemp: mktemp_path}}
    end
  end

  def ssh_host(device_id) when is_binary(device_id) do
    "atom-#{normalized_device_id(device_id)}-ssh"
  end

  def frp_endpoint do
    config = Application.get_env(:nixstasis, :ssh_client, [])

    host =
      Keyword.get(config, :frp_host) ||
        Application.get_env(:nixstasis, :base_domain) ||
        "example.com"

    port = Keyword.get(config, :frp_port) || "2022"

    {to_string(host), to_string(port)}
  end

  def ssh_user do
    "nixstasis-support"
  end

  def terminal_type do
    config = Application.get_env(:nixstasis, :ssh_client, [])
    config |> Keyword.get(:terminal_type, "xterm-256color") |> to_string()
  end

  @impl true
  def init(opts) do
    device_id = Keyword.fetch!(opts, :device_id)
    private_key = Keyword.fetch!(opts, :private_key)
    host_key = Keyword.get(opts, :host_key)
    channel_pid = Keyword.fetch!(opts, :channel_pid)
    columns = sane_dimension(Keyword.get(opts, :columns), 80)
    rows = sane_dimension(Keyword.get(opts, :rows), 24)

    case validate_executables(opts) do
      {:ok, executables} ->
        start_ssh_port(device_id, private_key, host_key, channel_pid, executables, columns, rows)

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp start_ssh_port(device_id, private_key, host_key, channel_pid, executables, columns, rows) do
    with {:ok, normalized_host_key} <- SshHostKey.normalize(host_key),
         {:ok, temp_dir} <- create_private_temp_dir(executables.mktemp) do
      key_path = write_temp_key(temp_dir, private_key)
      known_hosts_path = write_temp_known_hosts(temp_dir, device_id, normalized_host_key)
      tty_path = remote_tty_path()

      ssh_args =
        ssh_args(
          device_id,
          key_path,
          known_hosts_path,
          executables,
          remote_shell_command(tty_path, columns, rows)
        )

      args = ["TERM=#{terminal_type()}", executables.ssh | ssh_args]

      Logger.info("Starting SSH connection to #{device_id}...")

      port =
        Port.open({:spawn_executable, executables.env}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args
        ])

      {:ok,
       %{
         port: port,
         temp_dir: temp_dir,
         key_path: key_path,
         known_hosts_path: known_hosts_path,
         channel_pid: channel_pid,
         device_id: device_id,
         executables: executables,
         tty_path: tty_path,
         size: {columns, rows},
         resize_task: nil,
         pending_resize: nil
       }}
    else
      {:error, :invalid_ssh_host_key} -> {:stop, %{reason: :invalid_host_key}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_cast({:send_data, data}, state) do
    Port.command(state.port, data)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:resize, columns, rows}, state) do
    columns = sane_dimension(columns, nil)
    rows = sane_dimension(rows, nil)

    cond do
      is_nil(columns) or is_nil(rows) ->
        {:noreply, state}

      state.size == {columns, rows} ->
        {:noreply, %{state | pending_resize: nil}}

      state.resize_task ->
        {:noreply, %{state | pending_resize: {columns, rows}}}

      true ->
        {:noreply, start_resize_task(state, columns, rows)}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, pid, reason},
        %{resize_task: {pid, ref}} = state
      ) do
    if reason not in [:normal, :shutdown] do
      Logger.warning("Terminal resize worker exited unexpectedly: #{inspect(reason)}")
    end

    state = %{state | resize_task: nil}

    case state.pending_resize do
      nil ->
        {:noreply, state}

      size when size == state.size ->
        {:noreply, %{state | pending_resize: nil}}

      {columns, rows} ->
        state = %{state | pending_resize: nil}
        {:noreply, start_resize_task(state, columns, rows)}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    send(state.channel_pid, {:ssh_output, data})
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("SSH process exited with status: #{status}")
    send(state.channel_pid, {:ssh_exit, status})
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    stop_resize_task(state[:resize_task])

    if state[:temp_dir] do
      File.rm_rf(state.temp_dir)
    end

    :ok
  end

  defp create_private_temp_dir(mktemp_executable) do
    template = Path.join(System.tmp_dir!(), "nixstasis_ssh_client_XXXXXXXXXX")

    case System.cmd(mktemp_executable, ["-d", template], stderr_to_stdout: true) do
      {output, 0} ->
        path = String.trim(output)

        case File.stat(path) do
          {:ok, %File.Stat{type: :directory, mode: mode}} ->
            if Bitwise.band(mode, 0o777) == 0o700 do
              {:ok, path}
            else
              File.rm_rf(path)
              {:error, %{reason: :insecure_temp_directory}}
            end

          _ ->
            File.rm_rf(path)
            {:error, %{reason: :insecure_temp_directory}}
        end

      {output, status} ->
        {:error,
         %{
           reason: :temp_directory_creation_failed,
           status: status,
           output: String.trim(output)
         }}
    end
  end

  defp write_temp_key(dir, content) do
    path = Path.join(dir, "identity")
    write_private_temp_file(path, content)
    path
  end

  defp write_temp_known_hosts(dir, device_id, host_key) do
    path = Path.join(dir, "known_hosts")
    write_private_temp_file(path, "#{ssh_host(device_id)} #{host_key}\n")
    path
  end

  defp write_private_temp_file(path, content) do
    File.write!(path, content, [:exclusive])
    File.chmod!(path, 0o600)
  end

  defp find_required_executable(executable) do
    case System.find_executable(executable) do
      nil -> {:error, %{reason: :missing_executable, executable: executable}}
      path -> {:ok, path}
    end
  end

  defp ssh_args(device_id, key_path, known_hosts_path, executables, remote_command) do
    {frp_host, frp_port} = frp_endpoint()
    proxy_cmd = "#{executables.proxy} --proxy-type http --proxy #{frp_host}:#{frp_port} %h %p"

    [
      "-i",
      key_path,
      "-o",
      "ProxyCommand=#{proxy_cmd}",
      "-o",
      "StrictHostKeyChecking=yes",
      "-o",
      "UserKnownHostsFile=#{known_hosts_path}",
      "-o",
      "GlobalKnownHostsFile=/dev/null",
      "-o",
      "LogLevel=ERROR",
      "-tt",
      "#{ssh_user()}@#{ssh_host(device_id)}",
      remote_command
    ]
  end

  defp remote_shell_command(tty_path, columns, rows) do
    "sh -lc 'tty > #{tty_path}; stty rows #{rows} cols #{columns}; exec \"${SHELL:-/bin/sh}\" -l'"
  end

  defp remote_resize_command(tty_path, columns, rows) do
    "sh -lc 'tty_path=$(cat #{tty_path} 2>/dev/null); " <>
      "[ -n \"$tty_path\" ] && stty rows #{rows} cols #{columns} < \"$tty_path\" > \"$tty_path\"'"
  end

  defp start_resize_task(state, columns, rows) do
    {pid, ref} =
      spawn_monitor(fn ->
        resize_remote_tty(state, columns, rows)
      end)

    %{state | resize_task: {pid, ref}, size: {columns, rows}}
  end

  defp resize_remote_tty(state, columns, rows) do
    args =
      ssh_args(
        state.device_id,
        state.key_path,
        state.known_hosts_path,
        state.executables,
        remote_resize_command(state.tty_path, columns, rows)
      )

    System.cmd(state.executables.env, ["TERM=#{terminal_type()}", state.executables.ssh | args], stderr_to_stdout: true)

    :ok
  end

  defp stop_resize_task(nil), do: :ok

  defp stop_resize_task({pid, ref}) do
    Process.demonitor(ref, [:flush])

    if Process.alive?(pid) do
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp remote_tty_path do
    id = Ecto.UUID.generate() |> String.replace("-", "")
    "/tmp/nixstasis-terminal-#{id}.tty"
  end

  defp sane_dimension(value, _default)
       when is_integer(value) and value > 0 and value <= @max_terminal_dimension,
       do: value

  defp sane_dimension(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 and integer <= @max_terminal_dimension -> integer
      _ -> default
    end
  end

  defp sane_dimension(_value, default), do: default

  defp normalized_device_id(device_id) do
    device_id
    |> String.replace(~r/[^0-9A-Za-z]/, "")
    |> String.downcase()
  end
end
