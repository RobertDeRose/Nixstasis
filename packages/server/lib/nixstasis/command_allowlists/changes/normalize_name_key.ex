defmodule Nixstasis.CommandAllowlists.Changes.NormalizeNameKey do
  @moduledoc """
  Derives the case-insensitive command entry lookup key from the operator-facing name.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_change(changeset, :name) do
      {:ok, name} when is_binary(name) ->
        Ash.Changeset.change_attribute(changeset, :name_key, String.downcase(name))

      _ ->
        changeset
    end
  end
end
