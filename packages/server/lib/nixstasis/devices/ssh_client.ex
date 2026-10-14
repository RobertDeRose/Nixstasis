defmodule Nixstasis.Devices.SshClient do
  @moduledoc """
  SSH client for browser terminal sessions through the FRPS TCP mux endpoint.
  """
  use GenServer
  require Logger

  alias Nixstasis.Devices.SshHostKey

  @max_terminal_dimension 1_000
  @default_resize_timeout_ms 15_000
  # Bounds the separate resize connection so a stalled one exits on its own.
  @resize_ssh_options [
    "-o",
    "ConnectTimeout=10",
    "-o",
    "ServerAliveInterval=5",
    "-o",
    "ServerAliveCountMax=2"
  ]

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

  @doc """
  Resolves the executables an SSH session needs through `PATH`.

  Looks up `ssh`, `ncat`, `env`, and `mktemp` unless `:ssh_executable`,
  `:proxy_executable`, `:env_executable`, or `:mktemp_executable` names another
  executable. Returns `{:ok, %{ssh: path, proxy: path, env: path, mktemp: path}}`,
  or `{:error, %{reason: :missing_executable, executable: name}}` for the first
  executable that cannot be found.
  """
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

  # Starts the interactive SSH session for init/1. Writes the pinned host key and
  # the session private key into a new owner-only temp directory, then spawns
  # `env TERM=... ssh ...` as a port that reaches the device through the FRP proxy.
  # Returns `{:ok, state}`, or `{:stop, reason}` when the host key is invalid or
  # the temp directory cannot be created. If setup raises after the directory
  # exists, the directory is removed before the error is re-raised.
  defp start_ssh_port(device_id, private_key, host_key, channel_pid, executables, columns, rows) do
    with {:ok, normalized_host_key} <- SshHostKey.normalize(host_key),
         {:ok, temp_dir} <- create_private_temp_dir(executables.mktemp) do
      known_hosts_path = Path.join(temp_dir, "known_hosts")
      key_path = Path.join(temp_dir, "identity")

      try do
        write_private_file!(known_hosts_path, "#{ssh_host(device_id)} #{normalized_host_key}\n")
        write_private_file!(key_path, private_key)
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
      rescue
        error ->
          # terminate/2 does not run when init/1 raises, so remove the session
          # credentials here instead of stranding the private key on disk.
          File.rm_rf(temp_dir)
          reraise error, __STACKTRACE__
      end
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
        %{resize_task: {pid, ref, previous_size, timer}} = state
      ) do
    Process.cancel_timer(timer)

    # A crashed worker did not apply its size, so restore the last applied size
    # to keep a retry of the same dimensions from being skipped.
    if reason in [:normal, :shutdown] do
      finish_resize_task(state, state.size)
    else
      Logger.warning("Terminal resize worker exited unexpectedly: #{inspect(reason)}")
      finish_resize_task(state, previous_size)
    end
  end

  # A stalled resize connection must not hold the single worker slot forever.
  def handle_info({:resize_timeout, ref}, %{resize_task: {pid, ref, previous_size, _timer}} = state) do
    Logger.warning("Terminal resize worker timed out")
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    finish_resize_task(state, previous_size)
  end

  # The timer can fire after its worker already finished; ignore it then.
  def handle_info({:resize_timeout, _stale_ref}, state), do: {:noreply, state}

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

  # Stops any in-flight resize task and removes the session's temporary
  # credential directory when the server stops itself or is stopped with stop/1.
  # It does not run when init/1 fails; start_ssh_port/7 cleans up in that case.
  @impl true
  def terminate(_reason, state) do
    stop_resize_task(state[:resize_task])

    if state[:temp_dir] do
      File.rm_rf(state.temp_dir)
    end

    :ok
  end

  # Creates the session credential directory with `mktemp -d`, so its name is
  # unpredictable, and verifies that it is a directory with exactly 0700
  # permissions. Both credential files live inside it, so cleanup is one removal.
  # Returns `{:ok, path}`. A failed mktemp returns `:temp_directory_creation_failed`
  # with its exit status and output; any other file type or mode removes the path
  # and returns `:insecure_temp_directory`.
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

  # Restricts permissions before writing so key material is never readable under
  # the default umask, even briefly.
  defp write_private_file!(path, content) do
    File.write!(path, "", [:exclusive])
    File.chmod!(path, 0o600)
    File.write!(path, content)
  end

  defp find_required_executable(executable) do
    case System.find_executable(executable) do
      nil -> {:error, %{reason: :missing_executable, executable: executable}}
      path -> {:ok, path}
    end
  end

  defp ssh_args(device_id, key_path, known_hosts_path, executables, remote_command, extra_options \\ []) do
    {frp_host, frp_port} = frp_endpoint()
    proxy_cmd = "#{executables.proxy} --proxy-type http --proxy #{frp_host}:#{frp_port} %h %p"

    extra_options ++
      [
        "-i",
        key_path,
        "-o",
        "ProxyCommand=#{proxy_cmd}",
        "-o",
        "StrictHostKeyChecking=yes",
        "-o",
        "HostKeyAlgorithms=ssh-ed25519",
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

    timer = Process.send_after(self(), {:resize_timeout, ref}, resize_timeout_ms())
    %{state | resize_task: {pid, ref, state.size, timer}, size: {columns, rows}}
  end

  defp finish_resize_task(state, size) do
    state = %{state | resize_task: nil, size: size}

    case state.pending_resize do
      nil ->
        {:noreply, state}

      pending when pending == state.size ->
        {:noreply, %{state | pending_resize: nil}}

      {columns, rows} ->
        state = %{state | pending_resize: nil}
        {:noreply, start_resize_task(state, columns, rows)}
    end
  end

  defp resize_timeout_ms do
    :nixstasis
    |> Application.get_env(:ssh_client, [])
    |> Keyword.get(:resize_timeout_ms, @default_resize_timeout_ms)
  end

  defp resize_remote_tty(state, columns, rows) do
    args =
      ssh_args(
        state.device_id,
        state.key_path,
        state.known_hosts_path,
        state.executables,
        remote_resize_command(state.tty_path, columns, rows),
        @resize_ssh_options
      )

    System.cmd(state.executables.env, ["TERM=#{terminal_type()}", state.executables.ssh | args], stderr_to_stdout: true)

    :ok
  end

  defp stop_resize_task(nil), do: :ok

  defp stop_resize_task({pid, ref, _previous_size, timer}) do
    Process.cancel_timer(timer)
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
