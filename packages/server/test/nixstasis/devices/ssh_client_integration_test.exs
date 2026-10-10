defmodule Nixstasis.Devices.SshClientIntegrationTest do
  # Drives the real OpenSSH client against a local Erlang SSH daemon so host-key
  # pinning is proven end to end rather than inferred from command-line flags.
  use ExUnit.Case, async: false

  alias Nixstasis.Devices.SshClient

  # :ssh is not a dependency; setup_all adds it to the code path at runtime.
  @compile {:no_warn_undefined, :ssh}

  @device_id "11111111-2222-3333-4444-555555555555"
  @required_executables ["ssh", "ssh-keygen", "nc", "env"]

  setup_all do
    # Mix prunes OTP applications that are not dependencies from the code path.
    Mix.ensure_application!(:ssh)
    {:ok, _apps} = Application.ensure_all_started(:ssh)

    case Enum.reject(@required_executables, &System.find_executable/1) do
      [] -> :ok
      missing -> {:skip, "requires #{Enum.join(missing, ", ")}"}
    end
  end

  setup do
    Process.flag(:trap_exit, true)
    root = Path.join(System.tmp_dir!(), "nixstasis_ssh_integration_#{System.unique_integer([:positive])}")
    system_dir = Path.join(root, "system")
    user_dir = Path.join(root, "user")
    File.mkdir_p!(system_dir)
    File.mkdir_p!(user_dir)

    host_key = keygen!(Path.join(system_dir, "ssh_host_ed25519_key"))
    other_host_key = keygen!(Path.join(root, "other_host_key"))
    client_key_path = Path.join(root, "client_key")
    client_public_key = keygen!(client_key_path)
    File.write!(Path.join(user_dir, "authorized_keys"), client_public_key <> "\n")

    {:ok, daemon} =
      :ssh.daemon(0,
        system_dir: String.to_charlist(system_dir),
        user_dir: String.to_charlist(user_dir),
        auth_methods: ~c"publickey",
        exec: {:direct, fn _command -> {:ok, ~c"nixstasis-integration-shell-ready"} end}
      )

    {:ok, info} = :ssh.daemon_info(daemon)
    port = Keyword.fetch!(info, :port)

    # The proxy ignores its HTTP proxy arguments and pipes SSH straight to the daemon.
    proxy_path = Path.join(root, "proxy")
    File.write!(proxy_path, "#!/bin/sh\nexec nc 127.0.0.1 #{port}\n")
    File.chmod!(proxy_path, 0o700)

    on_exit(fn ->
      :ssh.stop_daemon(daemon)
      File.rm_rf!(root)
    end)

    %{
      host_key: host_key,
      other_host_key: other_host_key,
      private_key: File.read!(client_key_path),
      proxy_path: proxy_path
    }
  end

  test "connects when the device presents its enrolled host key", context do
    {:ok, pid} = start_client(context, context.host_key)

    assert collect_output(pid) =~ "nixstasis-integration-shell-ready"
  end

  test "refuses a device presenting a different host key before running a shell", context do
    {:ok, pid} = start_client(context, context.other_host_key)
    output = collect_output(pid)

    assert output =~ "Host key verification failed"
    refute output =~ "nixstasis-integration-shell-ready"
  end

  defp start_client(context, trusted_host_key) do
    SshClient.start_link(
      device_id: @device_id,
      private_key: context.private_key,
      host_key: trusted_host_key,
      channel_pid: self(),
      ssh_executable: "ssh",
      proxy_executable: context.proxy_path,
      env_executable: "env"
    )
  end

  defp collect_output(pid, acc \\ "") do
    receive do
      {:ssh_output, data} -> collect_output(pid, acc <> data)
      {:ssh_exit, _status} -> acc
    after
      10_000 ->
        flunk("SSH client did not exit; output so far: #{inspect(acc)}")
    end
  end

  defp keygen!(path) do
    {_, 0} = System.cmd("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "", "-f", path])
    path |> Kernel.<>(".pub") |> File.read!() |> String.trim()
  end
end
