defmodule Nixstasis.Devices.SshClientTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Devices.SshClient

  test "validate_executables reports missing ssh executable" do
    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-ssh"}} =
             SshClient.validate_executables(
               ssh_executable: "missing-nixstasis-ssh",
               proxy_executable: "sh"
             )
  end

  test "validate_executables reports missing proxy executable" do
    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-proxy"}} =
             SshClient.validate_executables(
               ssh_executable: "sh",
               proxy_executable: "missing-nixstasis-proxy"
             )
  end

  test "start_link reports missing executable before opening port" do
    Process.flag(:trap_exit, true)

    assert {:error, %{reason: :missing_executable, executable: "missing-nixstasis-ssh"}} =
             SshClient.start_link(
               device_mac: "AA:BB:CC:DD:EE:FF",
               private_key: "test-only-sensitive-key-material",
               channel_pid: self(),
               ssh_executable: "missing-nixstasis-ssh",
               proxy_executable: "sh"
             )
  end
end
