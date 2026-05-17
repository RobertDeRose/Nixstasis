defmodule Nixstasis.Monitoring.CommandQueueTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Devices.PendingCommand
  alias Nixstasis.Repo

  describe "command queue" do
    test "queue_command/2 adds command to queue" do
      {:ok, device} =
        Devices.register_device(%{mac_address: "11:11:11:11:11:11", product_name: "P1"})

      {:ok, command} = Devices.queue_command(device, %{"cmd" => "reboot"})
      assert command.status == :queued
      assert command.command_payload == %{"cmd" => "reboot"}
    end

    test "pop_pending_commands/1 returns and updates commands" do
      {:ok, device} =
        Devices.register_device(%{mac_address: "22:22:22:22:22:22", product_name: "P1"})

      {:ok, c1} = Devices.queue_command(device, %{"id" => 1})
      {:ok, _c2} = Devices.queue_command(device, %{"id" => 2})

      commands = Devices.pop_pending_commands(device)
      assert length(commands) == 2
      # Verify returned commands have correct payload
      payloads = Enum.map(commands, & &1.command_payload)
      assert %{"id" => 1} in payloads
      assert %{"id" => 2} in payloads

      # Check status update (assuming pop marks as delivered)
      # We need a get_pending_command! or similar to verify DB state
      # For now assuming we can fetch via repo directly or add helper
      # But since test uses DataCase, we can use Repo
      alias Nixstasis.Repo
      assert Repo.get!(PendingCommand, c1.id).status == :delivered
    end

    test "pop_pending_commands/1 does not return already delivered commands" do
      {:ok, device} =
        Devices.register_device(%{mac_address: "33:33:33:33:33:33", product_name: "P1"})

      {:ok, command} = Devices.queue_command(device, %{"id" => "once"})

      commands = Devices.pop_pending_commands(device)

      assert Enum.map(commands, & &1.id) == [command.id]
      assert Repo.get!(PendingCommand, command.id).status == :delivered
      assert Devices.pop_pending_commands(device) == []
    end
  end
end
