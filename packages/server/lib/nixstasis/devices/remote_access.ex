defmodule Nixstasis.Devices.RemoteAccess do
  @moduledoc "Database authority for lease selection, ownership, and atomic device projections."

  import Ecto.Query
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.RemoteAccessLease, as: Lease
  alias Nixstasis.Provisioning.Delivery
  alias Nixstasis.Repo

  # Provisioning owns the route until its delivery ends or is withdrawn, so a
  # new browser cannot interrupt an upload. Within each class, newest wins;
  # UUID breaks equal timestamp ties. Remaining leases resume after revocation.
  def selected(device_id) do
    with {:ok, device_id} <- Ecto.UUID.cast(device_id) do
      Repo.one(
        from l in active_query(),
          where: l.device_id == ^device_id,
          order_by: [
            desc: fragment("CASE WHEN ? = 'provisioning' THEN 1 ELSE 0 END", l.owner_kind),
            desc: l.inserted_at,
            desc: l.id
          ],
          limit: 1
      )
    else
      _ -> nil
    end
  end

  def get(id) do
    with {:ok, id} <- Ecto.UUID.cast(id), do: Repo.get(Lease, id), else: (_ -> nil)
  end

  def for_owner(kind, id) do
    with {:ok, id} <- Ecto.UUID.cast(id), do: Repo.get_by(Lease, owner_kind: kind, owner_id: id), else: (_ -> nil)
  end

  def for_kind(kind), do: Repo.all(from l in Lease, where: l.owner_kind == ^kind and is_nil(l.revoked_at))

  def active?(id) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.exists?(from l in active_query(), where: l.id == ^id)
    else
      _ -> false
    end
  end

  def open(device_id, attrs) do
    Repo.transaction(fn ->
      device = lock_device(device_id)
      if is_nil(device), do: Repo.rollback(:not_found)
      lease = for_owner(attrs.owner_kind, attrs.owner_id)

      lease =
        if lease do
          if lease.device_id != device_id or lease.profile != attrs.profile or not active?(lease.id),
            do: Repo.rollback(:inactive_authorization)

          lease
        else
          now = DateTime.utc_now()

          created =
            Repo.insert!(struct!(Lease, Map.merge(attrs, %{device_id: device_id, inserted_at: now, updated_at: now})))

          unless active?(created.id), do: Repo.rollback(:inactive_authorization)
          created
        end

      {project(device), lease}
    end)
  end

  def close(id) do
    case get(id) do
      nil ->
        {:ok, nil}

      lease ->
        Repo.transaction(fn ->
          device = lock_device(lease.device_id)

          if device do
            revoke(from l in Lease, where: l.id == ^lease.id)
            {project(device), lease}
          end
        end)
    end
  end

  def close_device(device_id) do
    Repo.transaction(fn ->
      device = lock_device(device_id)
      if is_nil(device), do: Repo.rollback(:not_found)
      revoke(from l in Lease, where: l.device_id == ^device_id)
      project(device)
    end)
  end

  def restore do
    # Old device-level flags cannot recreate authorization without a lease.
    leases = Repo.all(from l in Lease, where: is_nil(l.revoked_at))

    Enum.each(leases, fn lease ->
      unless active?(lease.id), do: close(lease.id)
    end)

    ids = Repo.all(from d in Device, where: d.remote_access_requested == true, select: d.id)

    Enum.each(Enum.uniq(ids ++ Enum.map(leases, & &1.device_id)), fn id ->
      {:ok, _} =
        Repo.transaction(fn ->
          if device = lock_device(id), do: project(device)
        end)
    end)

    Enum.filter(leases, &active?(&1.id))
  end

  defp active_query do
    now = DateTime.utc_now()

    from l in Lease,
      left_join: delivery in Delivery,
      on: l.owner_kind == "provisioning" and l.owner_id == delivery.id and l.device_id == delivery.device_id,
      where: is_nil(l.revoked_at) and l.expires_at > ^now,
      where:
        l.owner_kind != "provisioning" or
          (not is_nil(delivery.id) and is_nil(delivery.lease_withdrawn_at) and
             delivery.state in [:submitting, :submitted, :running, :indeterminate]),
      select: l
  end

  defp lock_device(id), do: Repo.one(from d in Device, where: d.id == ^id, lock: "FOR UPDATE")

  defp revoke(query) do
    now = DateTime.utc_now()
    Repo.update_all(from(l in query, where: is_nil(l.revoked_at)), set: [revoked_at: now, updated_at: now])
  end

  defp project(device) do
    lease = selected(device.id)

    Repo.update_all(from(d in Device, where: d.id == ^device.id),
      set: [
        remote_access_requested: not is_nil(lease),
        remote_access_profile: if(lease, do: lease.profile, else: device.remote_access_default_profile),
        remote_access_expires_at: if(lease, do: lease.expires_at),
        remote_access_owner: if(lease, do: lease.audit_owner),
        updated_at: DateTime.utc_now()
      ]
    )

    Repo.get!(Device, device.id)
  end
end
