defmodule Nixstasis.Devices.Changes.RemoteAccessProjection do
  @moduledoc "Keep public device access fields a projection, not an authorization source."
  use Ash.Resource.Change

  alias Nixstasis.Devices.RemoteAccess

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.action_type == :create do
      changeset
      |> Ash.Changeset.force_change_attribute(:remote_access_requested, false)
      |> Ash.Changeset.force_change_attribute(:remote_access_expires_at, nil)
      |> Ash.Changeset.force_change_attribute(:remote_access_owner, nil)
      |> Ash.Changeset.force_change_attribute(
        :remote_access_profile,
        Ash.Changeset.get_attribute(changeset, :remote_access_default_profile)
      )
    else
      profile_changed? = Ash.Changeset.changing_attribute?(changeset, :remote_access_profile)
      profile = Ash.Changeset.get_attribute(changeset, :remote_access_profile)

      # Unrelated updates must never persist a lease snapshot from changeset construction.
      changeset =
        Enum.reduce(
          [:remote_access_requested, :remote_access_profile, :remote_access_expires_at, :remote_access_owner],
          changeset,
          &Ash.Changeset.clear_change(&2, &1)
        )

      if profile_changed? do
        changeset
        |> Ash.Changeset.force_change_attribute(:remote_access_default_profile, profile)
        |> Ash.Changeset.after_action(fn _changeset, device ->
          # This hook runs inside the Ash transaction, after the update holds the row lock.
          RemoteAccess.sync_projection(device.id)
        end)
      else
        Ash.Changeset.after_action(changeset, fn _changeset, device ->
          # Return current summary fields without writing a projection on heartbeat/metadata updates.
          {:ok, RemoteAccess.refresh_projection(device)}
        end)
      end
    end
  end
end
