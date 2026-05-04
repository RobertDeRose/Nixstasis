defmodule Nixstasis.Devices.SshClientTest do
  use ExUnit.Case, async: true

  alias Nixstasis.Devices.SshClient

  test "ssh_host matches packaged frpc custom domain" do
    assert SshClient.ssh_host("AA:BB:CC:DD:EE:FF") == "atom-aabbccddeeff-ssh"
  end
end
