defmodule Nixstasis.Devices.SshClientTest do
  use ExUnit.Case, async: false

  alias Nixstasis.Devices.SshClient

  @host_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  test "validate_executables reports missing ssh executable" do
    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-ssh"}} =
             SshClient.validate_executables(
               ssh_executable: "missing-nixstasis-ssh",
               proxy_executable: "sh",
               env_executable: "env"
             )
  end

  test "validate_executables reports missing proxy executable" do
    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-proxy"}} =
             SshClient.validate_executables(
               ssh_executable: "sh",
               proxy_executable: "missing-nixstasis-proxy",
               env_executable: "env"
             )
  end

  test "validate_executables reports missing env executable" do
    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-env"}} =
             SshClient.validate_executables(
               ssh_executable: "sh",
               proxy_executable: "sh",
               env_executable: "missing-nixstasis-env"
             )
  end

  test "start_link reports missing executable before opening port" do
    Process.flag(:trap_exit, true)

    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-ssh"}} =
             SshClient.start_link(
               device_id: "11111111-2222-3333-4444-555555555555",
               private_key: "test-only-sensitive-key-material",
               channel_pid: self(),
               ssh_executable: "missing-nixstasis-ssh",
               proxy_executable: "sh",
               env_executable: "env"
             )
  end

  test "start_link rejects a missing or invalid trusted host key before opening SSH" do
    Process.flag(:trap_exit, true)

    assert {:error, %{reason: :invalid_host_key}} =
             SshClient.start_link(
               device_id: "11111111-2222-3333-4444-555555555555",
               private_key: "test-only-sensitive-key-material",
               host_key: "not-a-host-key",
               channel_pid: self(),
               ssh_executable: "sh",
               proxy_executable: "sh",
               env_executable: "env"
             )
  end

  test "ssh_host uses atom normalized device id SSH host" do
    assert SshClient.ssh_host("11111111-2222-3333-4444-555555555555") ==
             "atom-11111111222233334444555555555555-ssh"
  end

  test "frp_endpoint uses explicit ssh client config before base domain fallback" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)
    previous_base_domain = Application.get_env(:nixstasis, :base_domain)

    on_exit(fn ->
      restore_env(:ssh_client, previous_ssh_client)
      restore_env(:base_domain, previous_base_domain)
    end)

    Application.put_env(:nixstasis, :base_domain, "example.test")
    Application.put_env(:nixstasis, :ssh_client, frp_host: "frps", frp_port: 2222)

    assert SshClient.frp_endpoint() == {"frps", "2222"}
  end

  test "frp_endpoint falls back to base domain and default tcpmux port" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)
    previous_base_domain = Application.get_env(:nixstasis, :base_domain)

    on_exit(fn ->
      restore_env(:ssh_client, previous_ssh_client)
      restore_env(:base_domain, previous_base_domain)
    end)

    Application.delete_env(:nixstasis, :ssh_client)
    Application.put_env(:nixstasis, :base_domain, "example.test")

    assert SshClient.frp_endpoint() == {"example.test", "2022"}
  end

  test "ssh_user defaults to remote-support account" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)

    on_exit(fn -> restore_env(:ssh_client, previous_ssh_client) end)

    Application.delete_env(:nixstasis, :ssh_client)

    assert SshClient.ssh_user() == "nixstasis-support"
  end

  test "ssh_user ignores configured accounts other than nixstasis-support" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)

    on_exit(fn -> restore_env(:ssh_client, previous_ssh_client) end)

    Application.put_env(:nixstasis, :ssh_client, user: "support-admin")

    assert SshClient.ssh_user() == "nixstasis-support"
  end

  test "terminal_type defaults to xterm-256color" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)

    on_exit(fn -> restore_env(:ssh_client, previous_ssh_client) end)

    Application.delete_env(:nixstasis, :ssh_client)

    assert SshClient.terminal_type() == "xterm-256color"
  end

  test "terminal_type can be configured" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)

    on_exit(fn -> restore_env(:ssh_client, previous_ssh_client) end)

    Application.put_env(:nixstasis, :ssh_client, terminal_type: "vt100")

    assert SshClient.terminal_type() == "vt100"
  end

  test "start_link records remote tty and resize updates it without writing to terminal stdin" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)
    temp_dir = Path.join(System.tmp_dir!(), "nixstasis-ssh-client-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)

    env_path = Path.join(temp_dir, "env")
    log_path = Path.join(temp_dir, "commands.log")

    File.write!(env_path, """
    #!/bin/sh
    printf '%s\n' "$*" >> '#{log_path}'
    case "$*" in
      *'tty_path=$(cat'*) exit 0 ;;
      *) printf 'ready\n'; sleep 30 ;;
    esac
    """)

    File.chmod!(env_path, 0o700)

    on_exit(fn ->
      restore_env(:ssh_client, previous_ssh_client)
      File.rm_rf(temp_dir)
    end)

    Application.put_env(:nixstasis, :ssh_client,
      frp_host: "frps.test",
      frp_port: 2222,
      terminal_type: "xterm-256color"
    )

    {:ok, pid} =
      SshClient.start_link(
        device_id: "11111111-2222-3333-4444-555555555555",
        private_key: "test-only-sensitive-key-material",
        host_key: @host_key,
        channel_pid: self(),
        columns: 100,
        rows: 40,
        ssh_executable: "sh",
        proxy_executable: "sh",
        env_executable: env_path
      )

    assert_receive {:ssh_output, "ready\n"}, 1_000

    initial_commands = File.read!(log_path)
    SshClient.resize(pid, 1_001, 48)
    _ = :sys.get_state(pid)
    assert File.read!(log_path) == initial_commands

    SshClient.resize(pid, 120, 48)
    _ = :sys.get_state(pid)

    commands = eventually_read!(log_path, &String.contains?(&1, "tty_path=$(cat"))

    assert commands =~ "TERM=xterm-256color"
    assert commands =~ "StrictHostKeyChecking=yes"
    assert commands =~ "UserKnownHostsFile=/tmp/nixstasis_known_hosts_"
    assert commands =~ "GlobalKnownHostsFile=/dev/null"
    refute commands =~ "StrictHostKeyChecking=no"
    refute commands =~ "UserKnownHostsFile=/dev/null"
    assert commands =~ "tty > /tmp/nixstasis-terminal-"
    assert commands =~ "stty rows 40 cols 100"
    assert commands =~ "exec \"${SHELL:-/bin/sh}\" -l"
    assert commands =~ "tty_path=$(cat /tmp/nixstasis-terminal-"
    assert commands =~ "stty rows 48 cols 120 < \"$tty_path\" > \"$tty_path\""

    GenServer.stop(pid)
  end

  test "coalesces resize bursts and runs only one resize subprocess at a time" do
    previous_ssh_client = Application.get_env(:nixstasis, :ssh_client)

    temp_dir =
      Path.join(
        System.tmp_dir!(),
        "nixstasis-ssh-resize-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(temp_dir)

    env_path = Path.join(temp_dir, "env")
    log_path = Path.join(temp_dir, "resize.log")
    lock_path = Path.join(temp_dir, "resize.lock")

    File.write!(env_path, """
    #!/bin/sh
    case "$*" in
      *'tty_path=$(cat'*)
        if mkdir '#{lock_path}' 2>/dev/null; then
          printf 'resize-start %s\n' "$*" >> '#{log_path}'
          sleep 0.2
          printf 'resize-end %s\n' "$*" >> '#{log_path}'
          rmdir '#{lock_path}'
        else
          printf 'resize-overlap %s\n' "$*" >> '#{log_path}'
        fi
        exit 0
        ;;
      *)
        printf 'ready\n'
        sleep 30
        ;;
    esac
    """)

    File.chmod!(env_path, 0o700)

    on_exit(fn ->
      restore_env(:ssh_client, previous_ssh_client)
      File.rm_rf(temp_dir)
    end)

    Application.put_env(:nixstasis, :ssh_client,
      frp_host: "frps.test",
      frp_port: 2222,
      terminal_type: "xterm-256color"
    )

    {:ok, pid} =
      SshClient.start_link(
        device_id: "11111111-2222-3333-4444-555555555555",
        private_key: "test-only-sensitive-key-material",
        host_key: @host_key,
        channel_pid: self(),
        columns: 100,
        rows: 40,
        ssh_executable: "sh",
        proxy_executable: "sh",
        env_executable: env_path
      )

    assert_receive {:ssh_output, "ready\n"}, 1_000

    SshClient.resize(pid, 121, 41)

    for columns <- 122..160 do
      SshClient.resize(pid, columns, 41)
    end

    _ = :sys.get_state(pid)

    log =
      eventually_read!(
        log_path,
        fn value ->
          String.contains?(value, "resize-end") and String.contains?(value, "cols 160")
        end,
        200
      )

    refute log =~ "resize-overlap"
    assert length(Regex.scan(~r/^resize-start /m, log)) == 2
    assert log =~ "stty rows 41 cols 121"
    assert log =~ "stty rows 41 cols 160"

    GenServer.stop(pid)
  end

  defp restore_env(key, nil), do: Application.delete_env(:nixstasis, key)
  defp restore_env(key, value), do: Application.put_env(:nixstasis, key, value)

  defp eventually_read!(path, predicate, attempts \\ 50)

  defp eventually_read!(path, predicate, attempts) when attempts > 0 do
    value = if File.exists?(path), do: File.read!(path), else: ""

    if predicate.(value) do
      value
    else
      receive do
      after
        10 -> eventually_read!(path, predicate, attempts - 1)
      end
    end
  end

  defp eventually_read!(path, _predicate, 0), do: File.read!(path)
end
