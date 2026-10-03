defmodule Nixstasis.DevicesTest do
  use Nixstasis.DataCase

  import ExUnit.CaptureLog

  alias Nixstasis.Devices
  alias Nixstasis.Domain

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

    test "list_devices/1 composes group and authorization with every existing filter" do
      now = DateTime.utc_now()

      wanted =
        device_fixture(%{
          mac_address: "A1:A1:A1:A1:A1:A1",
          product_name: "alpha",
          account_number: "77777",
          ipv4_address: "10.0.0.1",
          approval_status: :approved,
          last_seen_at: DateTime.add(now, -30, :second)
        })

      unauthorized =
        device_fixture(%{
          mac_address: "A2:A2:A2:A2:A2:A2",
          product_name: "alpha",
          account_number: "77777",
          ipv4_address: "10.0.0.1",
          approval_status: :approved,
          last_seen_at: DateTime.add(now, -30, :second)
        })

      wrong_product =
        device_fixture(%{
          mac_address: "A3:A3:A3:A3:A3:A3",
          product_name: "beta",
          account_number: "77777",
          ipv4_address: "10.0.0.1",
          approval_status: :approved,
          last_seen_at: DateTime.add(now, -30, :second)
        })

      outside_group =
        device_fixture(%{
          mac_address: "A4:A4:A4:A4:A4:A4",
          product_name: "alpha",
          account_number: "77777",
          ipv4_address: "10.0.0.1",
          approval_status: :approved,
          last_seen_at: DateTime.add(now, -30, :second)
        })

      {:ok, group} = Domain.create_device_group(%{name: "Composed"})

      for device <- [wanted, unauthorized, wrong_product] do
        {:ok, _membership} =
          Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})
      end

      assert [result] =
               Devices.list_devices(
                 authorized_device_ids: MapSet.new([wanted.id, wrong_product.id, outside_group.id]),
                 filter: %{
                   group_id: group.id,
                   approval_status: :approved,
                   connectivity_status: :online,
                   product: "alpha",
                   account_number: "77777",
                   ipv4_address: "10.0.0.1"
                 },
                 search: "77777",
                 sort_by: :mac_address,
                 sort_order: :asc
               )

      assert result.id == wanted.id
      assert Devices.list_devices(filter: %{group_id: Ecto.UUID.generate()}) == []
      assert Devices.list_devices(authorized_device_ids: MapSet.new()) == []
    end

    test "list_devices/1 applies active group membership in one database statement" do
      device = device_fixture(%{mac_address: "A5:A5:A5:A5:A5:A5", product_name: "atomic"})
      {:ok, group} = Domain.create_device_group(%{name: "Atomic filter"})

      {:ok, _membership} =
        Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})

      handler_id = "group-filter-query-count-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:nixstasis, :repo, :query],
          fn _event, _measurements, _metadata, test_pid -> send(test_pid, :group_filter_query) end,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert [result] = Devices.list_devices(filter: %{group_id: group.id})
      assert result.id == device.id
      assert_receive :group_filter_query
      refute_receive :group_filter_query, 20
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

    test "set_remote_access/3 stores a validated route profile" do
      device = device_fixture()

      assert {:ok, updated} = Devices.set_remote_access(device, true, "bootstrap")
      assert updated.remote_access_requested == true
      assert updated.remote_access_profile == "bootstrap"

      assert {:ok, updated} = Devices.set_remote_access(updated, false)
      assert updated.remote_access_profile == "bootstrap"
    end

    test "set_remote_access/3 rejects unsafe route profile names" do
      device = device_fixture()

      assert {:error, :invalid_remote_access_profile} =
               Devices.set_remote_access(device, true, "../frpc.toml")
    end

    test "device re-registration preserves the operator-selected route profile" do
      device = device_fixture(%{mac_address: "02:00:00:00:00:11"})
      assert {:ok, device} = Devices.set_remote_access_profile(device, "bootstrap")

      assert {:ok, re_registered} =
               Devices.register_device(%{mac_address: device.mac_address, product_name: "key-v2"})

      assert re_registered.id == device.id
      assert re_registered.remote_access_profile == "bootstrap"
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

    test "update_device/2 rejects approval status regressions" do
      rejected = device_fixture(%{mac_address: "88:88:88:88:88:89", approval_status: :rejected})

      assert {:error, %Ash.Error.Invalid{}} =
               Devices.update_device(rejected, %{approval_status: :pending})

      assert Devices.get_device!(rejected.id).approval_status == :rejected
    end

    test "approve_device/1 forces secure registration before runtime auth" do
      pending = device_fixture(%{approval_status: :pending})

      assert {:ok, approved} = Devices.approve_device(pending)
      assert approved.approval_status == :approved
      assert is_nil(approved.api_token_hash)
      assert Devices.authenticate_device(approved, "token") == {:error, :missing_token}
    end

    test "register_public_device/1 rejects missing schema" do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Devices.register_public_device(%{
                 "mac_address" => "AA:BB:CC:DD:EE:A1",
                 "product_name" => "public-thermostat"
               })

      assert Exception.message(error) =~ "product"
    end

    test "register_public_device/1 rejects nil schema" do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Devices.register_public_device(%{
                 "mac_address" => "AA:BB:CC:DD:EE:A2",
                 "product_name" => "public-thermostat",
                 "schema" => nil
               })

      assert Exception.message(error) =~ "product"
    end

    test "register_public_device/1 rejects empty schema" do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Devices.register_public_device(%{
                 "mac_address" => "AA:BB:CC:DD:EE:A3",
                 "product_name" => "public-thermostat",
                 "schema" => %{}
               })

      assert Exception.message(error) =~ "product"
    end

    test "register_device/1 still allows internal registration without schema" do
      assert {:ok, device} =
               Devices.register_device(%{
                 "mac_address" => "AA:BB:CC:DD:EE:A4",
                 "product_name" => "internal-thermostat"
               })

      assert device.product_name == "internal-thermostat"
      assert device.schema == %{}
    end

    test "register_device/1 preserves existing ids when devices re-register" do
      assert {:ok, device} =
               Devices.register_device(%{
                 "mac_address" => "AA:BB:CC:DD:EE:A5",
                 "product_name" => "initial-product"
               })

      assert {:ok, _event} =
               Domain.create_telemetry_event(%{
                 device_id: device.id,
                 payload: %{},
                 timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
               })

      assert {:ok, registered_again} =
               Devices.register_device(%{
                 "mac_address" => "AA:BB:CC:DD:EE:A5",
                 "product_name" => "updated-product"
               })

      assert registered_again.id == device.id
      assert registered_again.product_name == "updated-product"
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

    test "command_result_status/2 distinguishes successful and failed acknowledgements" do
      device = device_fixture(%{mac_address: "77:66:66:66:66:66", approval_status: :approved})
      {:ok, ok_command} = Devices.queue_command(device, %{"id" => 1})
      {:ok, failed_command} = Devices.queue_command(device, %{"id" => 2})

      assert Devices.command_result_status(device.id, ok_command.id) == :pending

      assert {:ok, 2} =
               Devices.acknowledge_command_results(device, [
                 %{"command_id" => ok_command.id, "status" => "OK"},
                 %{"command_id" => failed_command.id, "status" => "FAILED", "error" => "missing public key"}
               ])

      assert Devices.command_result_status(device.id, ok_command.id) == :ok
      assert Devices.command_result_status(device.id, failed_command.id) == :failed
    end
  end

  describe "terminal_authorization_status/3" do
    test "binds authorization status to the command type and session ref" do
      device = device_fixture(%{mac_address: "78:78:78:78:78:78", approval_status: :approved})
      session_ref = Ecto.UUID.generate()

      payload = %{
        "type" => "ssh_authorize",
        "payload" => %{
          "content_type" => "application/vnd.nixstasis.ssh-authorize+json;version=1",
          "name" => session_ref,
          "data" => Jason.encode!(%{"session_ref" => session_ref})
        }
      }

      {:ok, command} = Devices.queue_command(device, payload)
      assert Devices.terminal_authorization_status(device.id, command.id, session_ref) == {:ok, :pending}

      assert Devices.terminal_authorization_status(device.id, command.id, Ecto.UUID.generate()) ==
               {:error, :session_mismatch}

      assert {:ok, 1} =
               Devices.acknowledge_command_results(device, [
                 %{"command_id" => command.id, "status" => "OK"}
               ])

      assert Devices.terminal_authorization_status(device.id, command.id, session_ref) == {:ok, :ok}

      assert Devices.terminal_authorization_status(device.id, "not-a-uuid", session_ref) ==
               {:error, :invalid_command_id}

      assert Devices.terminal_authorization_status(device.id, nil, session_ref) ==
               {:error, :missing_command_id}
    end

    test "rejects a non-ssh authorization command" do
      device = device_fixture(%{mac_address: "79:79:79:79:79:79", approval_status: :approved})
      {:ok, command} = Devices.queue_command(device, %{"type" => "diagnostic"})

      assert Devices.terminal_authorization_status(device.id, command.id, Ecto.UUID.generate()) ==
               {:error, :invalid_command_type}
    end
  end

  describe "queue_command_policy_assignment/1" do
    test "queues apply_command_policy and supersedes older queued policy commands" do
      device = device_fixture(%{mac_address: "71:71:71:71:71:71", approval_status: :approved})

      {:ok, old_assignment} =
        Domain.create_command_policy_assignment(%{
          device_id: device.id,
          revision: 1,
          version: "policy-1",
          resolved_policy: %{"commands" => %{"df" => "/usr/bin/df"}}
        })

      {:ok, new_assignment} =
        Domain.create_command_policy_assignment(%{
          device_id: device.id,
          revision: 2,
          version: "policy-2",
          resolved_policy: %{"commands" => %{"df" => "/usr/bin/df", "ip" => "/usr/sbin/ip"}}
        })

      assert {:ok, _} = Devices.queue_command_policy_assignment(old_assignment)
      assert {:ok, _} = Devices.queue_command_policy_assignment(new_assignment)

      [command] = Devices.pop_pending_commands(device)
      assert command.command_payload["type"] == "apply_command_policy"
      assert command.command_payload["payload_ref"] == new_assignment.id
      refute command.command_payload["payload_ref"] == old_assignment.id
    end
  end

  describe "queue_terminal_revoke/2" do
    test "returns :ok for empty session_ref without queuing anything" do
      device = device_fixture(%{mac_address: "70:70:70:70:70:70", approval_status: :approved})

      assert :ok = Devices.queue_terminal_revoke(device, "")

      assert [] = Devices.pop_pending_commands(device)
    end

    test "queues an ssh_revoke command" do
      device = device_fixture(%{mac_address: "72:72:72:72:72:72", approval_status: :approved})

      assert :ok = Devices.queue_terminal_revoke(device, "session-abc")

      [command] = Devices.pop_pending_commands(device)
      assert command.command_payload["type"] == "ssh_revoke"

      payload = command.command_payload["payload"]
      assert payload["name"] == "session-abc"
      assert payload["content_type"] == "application/vnd.nixstasis.ssh-revoke+json;version=1"

      assert %{"session_ref" => "session-abc"} = Jason.decode!(payload["data"])
    end

    test "does not queue duplicate revokes for a known session ref" do
      device = device_fixture(%{mac_address: "74:74:74:74:74:74", approval_status: :approved})

      assert :ok = Devices.queue_terminal_revoke(device, "session-deduplicated")
      assert :ok = Devices.queue_terminal_revoke(device, "session-deduplicated")

      commands = Devices.pop_pending_commands(device)
      assert length(commands) == 1
      assert hd(commands).command_payload["type"] == "ssh_revoke"
    end

    test "logs queue failures without blocking terminal cleanup" do
      device = device_fixture(%{mac_address: "73:73:73:73:73:73", approval_status: :approved})
      missing_device = %{device | id: Ecto.UUID.generate()}

      log =
        capture_log(fn ->
          assert :ok = Devices.queue_terminal_revoke(missing_device, "session-missing")
        end)

      assert log =~ "failed to queue terminal revoke for device #{missing_device.id}"
    end
  end
end
