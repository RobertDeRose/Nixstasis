defmodule Nixstasis.Devices.Changes.NormalizeGroupName do
  @moduledoc """
  Trims a device group name and derives its case-insensitive uniqueness key.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :name) do
      {:ok, name} when is_binary(name) ->
        trimmed = String.trim(name)

        changeset
        |> Ash.Changeset.change_attribute(:name, trimmed)
        |> Ash.Changeset.change_attribute(:name_key, :string.casefold(trimmed))

      _ ->
        changeset
    end
  end
end
