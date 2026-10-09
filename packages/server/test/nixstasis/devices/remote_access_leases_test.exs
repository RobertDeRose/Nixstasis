defmodule Nixstasis.Devices.RemoteAccessLeasesTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Devices.FrpsToken
  alias Nixstasis.Devices.RemoteAccess
  alias Nixstasis.Devices.RemoteAccessLease

  test "restart preserves every lease identity and permits selective revocation" do
    device = device()
    {:ok, _, first} = Devices.open_remote_access_lease(device, ttl_ms: 60_000, audit_owner: "first")
    {:ok, _, second} = Devices.open_remote_access_lease(device, ttl_ms: 30_000, audit_owner: "second")
    restart_manager()
    assert Devices.remote_access_lease_active?(first)
    assert Devices.remote_access_lease_active?(second)
    assert :ok = Devices.close_remote_access_lease(second)
    assert Devices.remote_access_lease_active?(first)
    assert Devices.get_device!(device.id).remote_access_owner == "first"
  end

  test "newest lease selects its own profile and expiry and closing it restores the previous lease" do
    device = device()
    {:ok, original, first} = Devices.open_remote_access_lease(device, profile: "default", ttl_ms: 60_000)
    {:ok, selected, second} = Devices.open_remote_access_lease(device, profile: "atomixos-bootstrap", ttl_ms: 30_000)
    assert selected.remote_access_profile == "atomixos-bootstrap"
    assert DateTime.compare(selected.remote_access_expires_at, original.remote_access_expires_at) == :lt
    token = FrpsToken.for_heartbeat(selected)
    assert {:ok, %{"lease_id" => ^second, "profile" => "atomixos-bootstrap"}} = FrpsToken.verify(token)
    assert :ok = Devices.close_remote_access_lease(second)
    restored = Devices.get_device!(device.id)
    assert restored.remote_access_profile == "default"
    assert restored.remote_access_expires_at == original.remote_access_expires_at
    assert Devices.remote_access_lease_active?(first)
    assert {:error, :inactive_authorization} = FrpsToken.verify(token)
  end

  test "credentials cannot borrow authorization from another lease" do
    device = device()
    {:ok, first_device, first} = Devices.open_remote_access_lease(device, ttl_ms: 60_000)
    first_token = FrpsToken.for_heartbeat(first_device)
    {:ok, second_device, second} = Devices.open_remote_access_lease(device, ttl_ms: 60_000)
    second_token = FrpsToken.for_heartbeat(second_device)
    assert {:error, :inactive_authorization} = FrpsToken.verify(first_token)
    assert :ok = Devices.close_remote_access_lease(second)
    assert {:error, :inactive_authorization} = FrpsToken.verify(second_token)
    assert {:ok, %{"lease_id" => ^first}} = FrpsToken.verify(first_token)
    assert :ok = Devices.close_remote_access_lease(first)
    assert {:error, :inactive_authorization} = FrpsToken.verify(first_token)
  end

  test "expiry is enforced before timers run and concurrent revocation cannot restore an expired lease" do
    device = device()
    {:ok, first_device, first} = Devices.open_remote_access_lease(device, ttl_ms: 60_000)
    first_token = FrpsToken.for_heartbeat(first_device)
    {:ok, second_device, second} = Devices.open_remote_access_lease(device, profile: "bootstrap", ttl_ms: 30_000)
    second_token = FrpsToken.for_heartbeat(second_device)
    manager = Process.whereis(Devices.RemoteAccessLeases)
    :ok = :sys.suspend(manager)

    try do
      Repo.update_all(from(l in RemoteAccessLease, where: l.id == ^second),
        set: [expires_at: DateTime.add(DateTime.utc_now(), -1, :second)]
      )

      refute RemoteAccess.active?(second)
      assert RemoteAccess.selected(device.id).id == first
      assert {:error, :inactive_authorization} = FrpsToken.verify(second_token)
      assert {:ok, %{"lease_id" => ^first}} = FrpsToken.verify(first_token)
      # The stale device projection and delayed timer cannot authorize the expired profile.
      assert Devices.get_device!(device.id).remote_access_profile == "bootstrap"
    after
      :ok = :sys.resume(manager)
    end

    close = Task.async(fn -> Devices.close_remote_access_lease(first) end)
    send(manager, {:remote_access_lease_expired, second})
    assert :ok = Task.await(close)
    Devices.sync_remote_access_leases()
    assert is_nil(RemoteAccess.selected(device.id))
    refute Devices.get_device!(device.id).remote_access_requested
    restart_manager()
    assert is_nil(RemoteAccess.selected(device.id))
    refute Devices.remote_access_lease_active?(first)
    refute Devices.remote_access_lease_active?(second)
    assert {:error, :inactive_authorization} = FrpsToken.verify(first_token)
    assert {:error, :inactive_authorization} = FrpsToken.verify(second_token)
  end

  test "embedded credential expiry fails closed even when the lease remains active" do
    {:ok, opened, ref} = Devices.open_remote_access_lease(device())
    {:ok, claims} = FrpsToken.verify(FrpsToken.for_heartbeat(opened))

    expired =
      Phoenix.Token.sign(
        NixstasisWeb.Endpoint,
        "nixstasis-frp-lease-authorization-v2",
        Map.put(claims, "expires_at_ms", System.system_time(:millisecond) - 1)
      )

    assert Devices.remote_access_lease_active?(ref)
    assert {:error, :expired} = FrpsToken.verify(expired)
  end

  test "invalid durable ownership rolls back the lease and device projection" do
    device = device()
    {:ok, original, original_id} = Devices.open_remote_access_lease(device)

    assert {:error, :inactive_authorization} =
             Devices.open_remote_access_lease(device,
               owner_kind: "provisioning",
               owner_id: Ecto.UUID.generate(),
               profile: "atomixos-bootstrap"
             )

    assert Repo.aggregate(Nixstasis.Devices.RemoteAccessLease, :count) == 1
    assert Devices.get_device!(device.id).remote_access_expires_at == original.remote_access_expires_at
    assert Devices.remote_access_lease_active?(original_id)
  end

  test "opening access for a deleted device leaves no authorization" do
    device = device()
    :ok = Nixstasis.Domain.destroy_device(device)
    assert {:error, :not_found} = Devices.open_remote_access_lease(device)
    assert Repo.aggregate(Nixstasis.Devices.RemoteAccessLease, :count) == 0
  end

  test "configuration changes do not mutate an active lease's profile" do
    device = device()
    {:ok, opened, ref} = Devices.open_remote_access_lease(device, profile: "default")
    token = FrpsToken.for_heartbeat(opened)
    {:ok, configured} = Devices.set_remote_access_profile(opened, "bootstrap")
    assert configured.remote_access_profile == "default"
    assert configured.remote_access_default_profile == "bootstrap"
    assert {:ok, %{"profile" => "default"}} = FrpsToken.verify(token)
    Devices.close_remote_access_lease(ref)
    {:ok, next, _} = Devices.open_remote_access_lease(Devices.get_device!(device.id))
    assert next.remote_access_profile == "bootstrap"
  end

  test "a prepared heartbeat update cannot resurrect a concurrently closed lease projection" do
    stale = device()
    {:ok, _, ref} = Devices.open_remote_access_lease(stale, audit_owner: "closed-owner")
    update = prepare_update(stale, %{last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    assert :ok = Devices.close_remote_access_lease(ref)
    assert {:ok, _} = commit_update(update)
    persisted = Devices.get_device!(stale.id)
    refute persisted.remote_access_requested
    assert is_nil(persisted.remote_access_expires_at)
    assert is_nil(persisted.remote_access_owner)
    assert persisted.remote_access_profile == "default"
  end

  test "a prepared metadata update cannot clear a concurrently opened lease projection" do
    {:ok, stale, first} = Devices.open_remote_access_lease(device(), audit_owner: "old-owner")
    assert :ok = Devices.close_remote_access_lease(first)
    update = prepare_update(stale, %{product_name: "updated"})
    {:ok, opened, second} = Devices.open_remote_access_lease(stale, profile: "bootstrap", audit_owner: "new-owner")
    assert {:ok, updated} = commit_update(update)
    assert updated.remote_access_profile == "bootstrap"
    assert updated.remote_access_owner == "new-owner"
    persisted = Devices.get_device!(stale.id)
    assert persisted.product_name == "updated"
    assert persisted.remote_access_requested
    assert persisted.remote_access_profile == "bootstrap"
    assert persisted.remote_access_expires_at == opened.remote_access_expires_at
    assert persisted.remote_access_owner == "new-owner"
    assert RemoteAccess.selected(stale.id).id == second
  end

  test "a prepared preference update projects the current lease and preserves the future preference" do
    {:ok, stale, first} = Devices.open_remote_access_lease(device())
    assert :ok = Devices.close_remote_access_lease(first)
    update = prepare_update(stale, %{remote_access_profile: "operator-choice"})
    {:ok, opened, second} = Devices.open_remote_access_lease(stale, profile: "bootstrap", audit_owner: "new-owner")
    token = FrpsToken.for_heartbeat(opened)
    assert {:ok, updated} = commit_update(update)
    assert updated.remote_access_default_profile == "operator-choice"
    persisted = Devices.get_device!(stale.id)
    assert persisted.remote_access_requested
    assert persisted.remote_access_profile == "bootstrap"
    assert persisted.remote_access_expires_at == opened.remote_access_expires_at
    assert persisted.remote_access_owner == "new-owner"
    assert {:ok, %{"lease_id" => ^second, "profile" => "bootstrap"}} = FrpsToken.verify(token)
    assert :ok = Devices.close_remote_access_lease(second)
    assert Devices.get_device!(stale.id).remote_access_profile == "operator-choice"
  end

  test "preference and locked projection reconciliation roll back together" do
    {:ok, opened, ref} = Devices.open_remote_access_lease(device(), profile: "bootstrap")

    changeset =
      opened
      |> Ash.Changeset.for_update(:update, %{remote_access_profile: "operator-choice"})
      |> Ash.Changeset.after_action(fn _changeset, _device -> {:error, :forced_rollback} end)

    assert {:error, _} = Ash.update(changeset)
    persisted = Devices.get_device!(opened.id)
    assert persisted.remote_access_default_profile == "default"
    assert persisted.remote_access_profile == "bootstrap"
    assert persisted.remote_access_expires_at == opened.remote_access_expires_at
    assert RemoteAccess.selected(opened.id).id == ref
  end

  test "a device projection alone cannot authorize access" do
    device = device()

    Repo.update_all(from(d in Nixstasis.Devices.Device, where: d.id == ^device.id),
      set: [remote_access_requested: true, remote_access_expires_at: DateTime.add(DateTime.utc_now(), 3600)]
    )

    refute Devices.remote_access_active?(Devices.get_device!(device.id))
    assert is_nil(FrpsToken.for_heartbeat(Devices.get_device!(device.id)))
  end

  defp prepare_update(device, attrs) do
    parent = self()

    task =
      Task.async(fn ->
        changeset = Ash.Changeset.for_update(device, :update, attrs)
        send(parent, {:update_prepared, self()})

        receive do
          :commit -> Ash.update(changeset)
        after
          5_000 -> raise "prepared update was not resumed"
        end
      end)

    on_exit(fn -> if Process.alive?(task.pid), do: Process.exit(task.pid, :kill) end)
    assert_receive {:update_prepared, pid}
    assert pid == task.pid
    task
  end

  defp commit_update(task) do
    send(task.pid, :commit)
    Task.await(task)
  end

  defp device do
    {:ok, device} = Devices.create_device(%{mac_address: "02:00:00:99:00:01", approval_status: :approved})
    device
  end

  defp restart_manager do
    :ok = Supervisor.terminate_child(Nixstasis.Supervisor, Devices)
    {:ok, _} = Supervisor.restart_child(Nixstasis.Supervisor, Devices)
    Devices.sync_remote_access_leases()
  end
end
