defmodule Nixstasis.Settings.Changes.NormalizeValue do
  @moduledoc "Validates and normalizes known settings at the shared resource mutation boundary."

  use Ash.Resource.Change

  alias Nixstasis.Settings

  @impl true
  def change(changeset, _opts, _context) do
    key = Ash.Changeset.get_attribute(changeset, :key)
    value = Ash.Changeset.get_attribute(changeset, :value)

    case Settings.normalize_value(key, value, changeset.data.value) do
      {:ok, normalized} ->
        Ash.Changeset.change_attribute(changeset, :value, normalized)

      {:error, message} ->
        Ash.Changeset.add_error(changeset, field: :value, message: message)
    end
  end
end
