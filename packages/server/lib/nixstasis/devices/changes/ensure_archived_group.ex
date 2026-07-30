defmodule Nixstasis.Devices.Changes.EnsureArchivedGroup do
  @moduledoc """
  Locks and verifies the persisted group before permanent deletion.
  """

  use Ash.Resource.Change

  import Ecto.Query, only: [from: 2]

  alias Ash.Error.Changes.InvalidAttribute
  alias Nixstasis.Repo

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      archived? =
        from(group in "device_groups",
          where: group.id == type(^changeset.data.id, Ecto.UUID),
          lock: "FOR UPDATE",
          select: not is_nil(group.archived_at)
        )
        |> Repo.one()

      if archived? do
        changeset
      else
        Ash.Changeset.add_error(
          changeset,
          InvalidAttribute.exception(
            field: :archived_at,
            message: "must be archived before permanent deletion"
          )
        )
      end
    end)
  end
end
