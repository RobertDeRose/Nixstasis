defmodule Nixstasis.Devices.SshKeyManagerTest do
  use ExUnit.Case, async: true
  alias Nixstasis.Devices.SshKeyManager

  test "generates ed25519 key pair" do
    assert {:ok, %{private_key: priv, public_key: pub}} =
             SshKeyManager.generate_key_pair(type: :ed25519)

    assert String.starts_with?(priv, "-----BEGIN OPENSSH PRIVATE KEY-----")
    assert String.starts_with?(pub, "ssh-ed25519")
  end

  test "generates rsa key pair" do
    assert {:ok, %{private_key: priv, public_key: pub}} =
             SshKeyManager.generate_key_pair(type: :rsa)

    assert String.starts_with?(priv, "-----BEGIN OPENSSH PRIVATE KEY-----")
    assert String.starts_with?(pub, "ssh-rsa")
  end
end
