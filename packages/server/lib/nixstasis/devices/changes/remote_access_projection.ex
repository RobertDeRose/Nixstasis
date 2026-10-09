defmodule Nixstasis.Devices.Changes.RemoteAccessProjection do
  @moduledoc "Keep public device access fields a projection, not an authorization source."
  use Ash.Resource.Change

  alias Nixstasis.Devices.RemoteAccess

  @impl true
  def change(changeset, _opts, _context) do
    changeset =
      if Ash.Changeset.changing_attribute?(changeset, :remote_access_profile) do
        Ash.Changeset.force_change_attribute(
          changeset,
          :remote_access_default_profile,
          Ash.Changeset.get_attribute(changeset, :remote_access_profile)
        )
      else
        changeset
      end

    lease = RemoteAccess.selected(Map.get(changeset.data, :id))

    changeset
    |> Ash.Changeset.force_change_attribute(:remote_access_requested, not is_nil(lease))
    |> Ash.Changeset.force_change_attribute(:remote_access_expires_at, if(lease, do: lease.expires_at))
    |> Ash.Changeset.force_change_attribute(:remote_access_owner, if(lease, do: lease.audit_owner))
    |> Ash.Changeset.force_change_attribute(
      :remote_access_profile,
      if(lease, do: lease.profile, else: Ash.Changeset.get_attribute(changeset, :remote_access_default_profile))
    )
  end
end
