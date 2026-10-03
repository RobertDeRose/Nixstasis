defmodule Nixstasis.Devices.SshKeyManagerTest do
  use ExUnit.Case, async: true
  alias Nixstasis.Devices.SshKeyManager

  test "uses a one-hour terminal session lifetime contract" do
    assert SshKeyManager.terminal_session_ttl_seconds() == 3_600
  end

  test "generates ed25519 key pair" do
    assert {:ok, %{private_key: priv, public_key: pub}} =
             SshKeyManager.generate_key_pair(type: :ed25519)

    assert priv =~ "OPENSSH"
    assert String.starts_with?(pub, "ssh-ed25519")
  end

  test "generates rsa key pair" do
    assert {:ok, %{private_key: priv, public_key: pub}} =
             SshKeyManager.generate_key_pair(type: :rsa)

    assert priv =~ "OPENSSH"
    assert String.starts_with?(pub, "ssh-rsa")
  end

  test "stores terminal private keys behind opaque session refs" do
    private_key = "test-only-sensitive-key-material"
    {:ok, session_ref} = SshKeyManager.create_terminal_session("device-1", private_key)

    refute session_ref =~ "secret"
    assert :undefined = :ets.whereis(:nixstasis_terminal_sessions)

    assert {:ok, %{private_key: ^private_key}} =
             SshKeyManager.fetch_terminal_session(session_ref, "device-1")

    assert :ok = SshKeyManager.clear_terminal_session(session_ref)
    assert :ok = SshKeyManager.clear_terminal_session(session_ref)
    assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, "device-1")
  end

  test "expires terminal session refs" do
    {:ok, session_ref} = SshKeyManager.create_terminal_session("device-1", "secret", ttl_ms: -1)

    refute SshKeyManager.terminal_session_active?(session_ref)
    assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, "device-1")
  end

  test "actively purges expired terminal session refs" do
    {:ok, session_ref} = SshKeyManager.create_terminal_session("device-1", "secret")
    assert SshKeyManager.terminal_session_active?(session_ref)

    manager = Process.whereis(Nixstasis.Devices.SshKeyManager.TerminalSessions)
    send(manager, {:terminal_session_expired, session_ref})
    :sys.get_state(manager)

    refute SshKeyManager.terminal_session_active?(session_ref)
    assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, "device-1")
  end
end
