defmodule Nixstasis.Devices.SshHostKeyTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Devices.SshHostKey

  @host_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

  test "normalizes an OpenSSH host public key and removes comments" do
    assert {:ok, @host_key} = SshHostKey.normalize(@host_key <> " root@device")
  end

  test "rejects an algorithm that does not match the key blob" do
    assert {:error, :invalid_ssh_host_key} =
             SshHostKey.normalize("ssh-rsa AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
  end

  test "rejects RSA and ECDSA host keys" do
    rsa = encode_key("ssh-rsa", [<<1, 0, 1>>, <<0>> <> :crypto.strong_rand_bytes(256)])
    {ecdsa_point, _private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    ecdsa = encode_key("ecdsa-sha2-nistp256", ["nistp256", ecdsa_point])

    for key <- [rsa, ecdsa] do
      assert {:error, :invalid_ssh_host_key} = SshHostKey.normalize(key)
    end
  end

  test "rejects truncated, padded, or mismatched key bodies" do
    invalid = [
      encode_key("ssh-ed25519", []),
      encode_key("ssh-ed25519", [:crypto.strong_rand_bytes(31)]),
      "ssh-ed25519 " <> Base.encode64(Base.decode64!(@host_key |> String.split() |> List.last()) <> <<0>>)
    ]

    for key <- invalid do
      assert {:error, :invalid_ssh_host_key} = SshHostKey.normalize(key), "accepted #{key}"
    end
  end

  test "returns an OpenSSH-style SHA256 fingerprint" do
    assert {:ok, "SHA256:" <> fingerprint} = SshHostKey.fingerprint(@host_key)
    refute fingerprint == ""
    refute String.contains?(fingerprint, "=")
  end

  defp encode_key(algorithm, fields) do
    blob = Enum.map_join([algorithm | fields], &(<<byte_size(&1)::unsigned-big-integer-size(32)>> <> &1))
    algorithm <> " " <> Base.encode64(blob)
  end
end
