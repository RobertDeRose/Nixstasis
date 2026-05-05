defmodule Nixstasis.DevicesTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices

  describe "devices" do
    @valid_attrs %{mac_address: "AA:BB:CC:DD:EE:FF", product_name: "key"}

    def device_fixture(attrs \\ %{}) do
      {:ok, device} =
        attrs
        |> Enum.into(@valid_attrs)
        |> Devices.create_device()

      device
    end

    test "list_devices/0 returns all devices" do
      device = device_fixture()
      assert [result] = Devices.list_devices()
      assert result.id == device.id
    end

    test "list_devices/1 filters by approval_status" do
      pending =
        device_fixture(%{
          mac_address: "11:11:11:11:11:11",
          product_name: "k1",
          approval_status: :pending
        })

      approved =
        device_fixture(%{
          mac_address: "22:22:22:22:22:22",
          product_name: "k2",
          approval_status: :approved
        })

      rejected =
        device_fixture(%{
          mac_address: "88:88:88:88:88:88",
          product_name: "k3",
          approval_status: :rejected
        })

      assert [res] = Devices.list_devices(filter: %{approval_status: :pending})
      assert res.id == pending.id

      assert [res] = Devices.list_devices(filter: %{approval_status: :approved})
      assert res.id == approved.id

      assert [res] = Devices.list_devices(filter: %{approval_status: "rejected"})
      assert res.id == rejected.id
    end

    test "list_devices/1 does not treat status as an approval filter" do
      pending =
        device_fixture(%{
          mac_address: "99:99:99:99:99:99",
          product_name: "k1",
          approval_status: :pending
        })

      approved =
        device_fixture(%{
          mac_address: "AA:AA:AA:AA:AA:AA",
          product_name: "k2",
          approval_status: :approved
        })

      ids =
        Devices.list_devices(filter: %{status: :pending})
        |> Enum.map(& &1.id)

      assert pending.id in ids
      assert approved.id in ids
    end

    test "create_device/1 broadcasts a sanitized device_created event" do
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")

      {:ok, device} =
        Devices.create_device(%{
          mac_address: "AB:AB:AB:AB:AB:AB",
          product_name: "k1",
          metadata: %{"future_token" => "secret"}
        })

      assert_receive {:device_created, payload}
      assert payload.id == device.id
      assert payload.approval_status == device.approval_status
      refute Map.has_key?(payload, :metadata)
      refute Map.has_key?(payload, :schema)
    end

    test "list_devices/1 filters by connectivity_status" do
      now = DateTime.utc_now()

      online =
        device_fixture(%{
          mac_address: "55:55:55:55:55:55",
          product_name: "k1",
          last_seen_at: DateTime.add(now, -60, :second)
        })

      offline =
        device_fixture(%{
          mac_address: "66:66:66:66:66:66",
          product_name: "k2",
          last_seen_at: DateTime.add(now, -10, :minute)
        })

      never_seen =
        device_fixture(%{
          mac_address: "77:77:77:77:77:77",
          product_name: "k3",
          last_seen_at: nil
        })

      assert [res] = Devices.list_devices(filter: %{connectivity_status: :online})
      assert res.id == online.id

      offline_ids =
        Devices.list_devices(filter: %{connectivity_status: "offline"})
        |> Enum.map(& &1.id)

      assert offline.id in offline_ids
      assert never_seen.id in offline_ids
      refute online.id in offline_ids
    end

    test "list_devices/1 filters by product and account number" do
      wanted =
        device_fixture(%{
          mac_address: "33:33:33:33:33:33",
          product_name: "alpha",
          account_number: "77777",
          approval_status: :approved
        })

      _other =
        device_fixture(%{
          mac_address: "44:44:44:44:44:44",
          product_name: "beta",
          account_number: "88888",
          approval_status: :approved
        })

      assert [res] =
               Devices.list_devices(filter: %{product: "alpha", account_number: "77777", approval_status: "approved"})

      assert res.id == wanted.id
    end

    test "list_devices/1 searches by mac_address" do
      match = device_fixture(%{mac_address: "11:22:33:44:55:66", product_name: "k1"})
      _miss = device_fixture(%{mac_address: "AA:BB:CC:DD:EE:FF", product_name: "k2"})

      assert [res] = Devices.list_devices(search: "11:22:33:44:55:66")
      assert res.id == match.id
    end

    test "approve_devices/1 approves multiple devices" do
      d1 =
        device_fixture(%{
          mac_address: "11:11:11:11:11:11",
          product_name: "k1",
          approval_status: :pending
        })

      d2 =
        device_fixture(%{
          mac_address: "22:22:22:22:22:22",
          product_name: "k2",
          approval_status: :pending
        })

      Devices.approve_devices([d1.id, d2.id])

      assert Devices.get_device!(d1.id).approval_status == :approved
      assert Devices.get_device!(d2.id).approval_status == :approved
      assert is_nil(Devices.get_device!(d1.id).api_token_hash)
      assert is_nil(Devices.get_device!(d2.id).api_token_hash)
    end

    test "reject_devices/1 rejects multiple devices" do
      d1 =
        device_fixture(%{
          mac_address: "11:11:11:11:11:11",
          product_name: "k1",
          approval_status: :pending
        })

      d2 =
        device_fixture(%{
          mac_address: "22:22:22:22:22:22",
          product_name: "k2",
          approval_status: :pending
        })

      Devices.reject_devices([d1.id, d2.id])

      assert Devices.get_device!(d1.id).approval_status == :rejected
      assert Devices.get_device!(d2.id).approval_status == :rejected
    end

    test "set_remote_access/2 toggles flag" do
      device = device_fixture()
      assert {:ok, updated} = Devices.set_remote_access(device, true)
      assert updated.remote_access_requested == true

      assert {:ok, updated} = Devices.set_remote_access(updated, false)
      assert updated.remote_access_requested == false
    end

    test "issue_device_token/1 stores only a non-plaintext token hash" do
      device = device_fixture(%{approval_status: :approved})

      assert {:ok, updated, token} = Devices.issue_device_token(device)
      assert is_binary(token)
      assert updated.api_token_hash != token
      assert byte_size(updated.api_token_hash) == 64
      assert Devices.authenticate_device(updated, token) == :ok
      assert Devices.authenticate_device(updated, "wrong") == {:error, :invalid_token}
    end

    test "create_device/1 does not accept api_token_hash" do
      assert {:error, _reason} =
               Devices.create_device(%{
                 mac_address: "77:77:77:77:77:77",
                 api_token_hash: String.duplicate("a", 64)
               })
    end

    test "update_device/2 does not accept api_token_hash" do
      device = device_fixture(%{mac_address: "88:88:88:88:88:88", approval_status: :approved})

      assert {:error, _reason} = Devices.update_device(device, %{api_token_hash: String.duplicate("b", 64)})
      assert is_nil(Devices.get_device!(device.id).api_token_hash)
    end

    test "approve_device/1 forces secure registration before runtime auth" do
      pending = device_fixture(%{approval_status: :pending})

      assert {:ok, approved} = Devices.approve_device(pending)
      assert approved.approval_status == :approved
      assert is_nil(approved.api_token_hash)
      assert Devices.authenticate_device(approved, "token") == {:error, :missing_token}
    end
  end

  describe "command queue boundaries" do
    test "pop_pending_commands/1 claims at most the per-poll limit" do
      device = device_fixture(%{mac_address: "55:55:55:55:55:55", approval_status: :approved})

      for index <- 1..55 do
        {:ok, _command} = Devices.queue_command(device, %{"id" => index})
      end

      commands = Devices.pop_pending_commands(device)

      assert length(commands) == 50
    end

    test "acknowledge_command_results/2 skips failed updates and continues" do
      device = device_fixture(%{mac_address: "66:66:66:66:66:66", approval_status: :approved})
      {:ok, command} = Devices.queue_command(device, %{"id" => 1})

      assert {:ok, 1} =
               Devices.acknowledge_command_results(device, [
                 %{"command_id" => "not-a-command", "status" => "OK"},
                 %{"command_id" => command.id, "status" => "OK"}
               ])
    end
  end
end
