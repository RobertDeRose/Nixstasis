defmodule Nixstasis.Devices.SshHostKeyTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Devices.SshHostKey

  @host_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

  test "normalizes an OpenSSH host public key and removes comments" do
    assert {:ok, @host_key} = SshHostKey.normalize(@host_key <> " root@device")
  end

  test "rejects an algorithm that does not match the key blob" do
    assert {:error, :invalid_ssh_host_key} =
             SshHostKey.normalize("ssh-rsa AAAAC3NzaC1lZDI1NTE5AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
  end

  test "returns an OpenSSH-style SHA256 fingerprint" do
    assert {:ok, "SHA256:" <> fingerprint} = SshHostKey.fingerprint(@host_key)
    refute fingerprint == ""
    refute String.contains?(fingerprint, "=")
  end
end
