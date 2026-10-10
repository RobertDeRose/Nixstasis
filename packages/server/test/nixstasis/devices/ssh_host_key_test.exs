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

  test "accepts complete RSA and ECDSA key bodies" do
    rsa = encode_key("ssh-rsa", [<<1, 0, 1>>, <<0>> <> :crypto.strong_rand_bytes(256)])
    assert {:ok, ^rsa} = SshHostKey.normalize(rsa)

    for {curve, named_curve} <- [{"nistp256", :secp256r1}, {"nistp384", :secp384r1}, {"nistp521", :secp521r1}] do
      ecdsa = encode_key("ecdsa-sha2-" <> curve, [curve, ec_point(named_curve)])
      assert {:ok, ^ecdsa} = SshHostKey.normalize(ecdsa)
    end
  end

  test "rejects truncated, padded, or mismatched key bodies" do
    invalid = [
      encode_key("ssh-ed25519", []),
      encode_key("ssh-ed25519", [:crypto.strong_rand_bytes(31)]),
      "ssh-ed25519 " <> Base.encode64(Base.decode64!(@host_key |> String.split() |> List.last()) <> <<0>>),
      encode_key("ssh-rsa", [<<1, 0, 1>>]),
      encode_key("ssh-rsa", ["", <<0>> <> :crypto.strong_rand_bytes(256)]),
      encode_key("ecdsa-sha2-nistp256", ["nistp384", ec_point(:secp256r1)]),
      encode_key("ecdsa-sha2-nistp256", ["nistp256", binary_part(ec_point(:secp256r1), 0, 64)]),
      encode_key("ecdsa-sha2-nistp256", ["nistp256", <<4>> <> :binary.copy(<<0>>, 64)]),
      encode_key("ecdsa-sha2-nistp256", ["nistp256", <<2>> <> :crypto.strong_rand_bytes(32)])
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

  defp ec_point(named_curve) do
    {public_key, _private_key} = :crypto.generate_key(:ecdh, named_curve)
    public_key
  end

  defp encode_key(algorithm, fields) do
    blob = Enum.map_join([algorithm | fields], &(<<byte_size(&1)::unsigned-big-integer-size(32)>> <> &1))
    algorithm <> " " <> Base.encode64(blob)
  end
end
