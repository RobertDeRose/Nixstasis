defmodule Nixstasis.Devices.SshClient do
  @moduledoc """
  A simple SSH client that connects to a device via an SSH tunnel using SSH command-line tool.
  It uses Elixir's Port to manage the SSH process and communicate with it.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @impl true
  def init(opts) do
    device_mac = Keyword.fetch!(opts, :device_mac)
    private_key = Keyword.fetch!(opts, :private_key)
    channel_pid = Keyword.fetch!(opts, :channel_pid)

    # Write private key to a temporary file
    key_path = write_temp_key(private_key)

    # Construct SSH command
    # We use -tt to force PTY allocation, which is needed for interactive shell
    # We use -o StrictHostKeyChecking=no because these are ephemeral connections to devices behind NAT
    # We use -o UserKnownHostsFile=/dev/null to avoid cluttering known_hosts
    ssh_cmd = "ssh"

    proxy_cmd = "ncat --proxy-type http --proxy #{frp_host()}:#{frp_port()} %h %p"

    args = [
      "-i",
      key_path,
      "-o",
      "ProxyCommand=#{proxy_cmd}",
      "-o",
      "StrictHostKeyChecking=no",
      "-o",
      "UserKnownHostsFile=/dev/null",
      # Reduce noise
      "-o",
      "LogLevel=ERROR",
      # Force PTY
      "-tt",
      "nixstasis@atomicnix-#{device_mac}-ssh"
    ]

    Logger.info("Starting SSH connection to #{device_mac}...")

    # Open the port
    # We use [:binary, :exit_status, :stderr_to_stdout] to handle data as binaries
    port =
      Port.open({:spawn_executable, System.find_executable(ssh_cmd)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    {:ok, %{port: port, key_path: key_path, channel_pid: channel_pid}}
  end

  @impl true
  def handle_cast({:send_data, data}, state) do
    Port.command(state.port, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    # Forward data to the channel
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
    # Cleanup temp key file
    if state[:key_path] do
      File.rm(state.key_path)
    end

    :ok
  end

  defp write_temp_key(content) do
    dir = System.tmp_dir!()
    id = Ecto.UUID.generate()
    path = Path.join(dir, "nixstasis_ssh_client_#{id}")
    File.write!(path, content)
    # SSH requires strict permissions
    File.chmod!(path, 0o600)
    path
  end

  defp frp_host do
    Application.get_env(:nixstasis, :ssh_client, [])
    |> Keyword.get(:frp_host, "device.<domain>")
  end

  defp frp_port do
    Application.get_env(:nixstasis, :ssh_client, [])
    |> Keyword.get(:frp_port, "2022")
  end
end
