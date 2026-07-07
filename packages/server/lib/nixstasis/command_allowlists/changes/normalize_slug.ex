defmodule Nixstasis.CommandAllowlists.Changes.NormalizeSlug do
  @moduledoc """
  Derives the category slug from the display name when a slug is not provided.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    slug =
      case Ash.Changeset.fetch_change(changeset, :slug) do
        {:ok, slug} when is_binary(slug) and slug != "" -> slug
        _ -> changed_display_name(changeset)
      end

    if is_binary(slug) do
      Ash.Changeset.change_attribute(changeset, :slug, String.downcase(slug))
    else
      changeset
    end
  end

  defp changed_display_name(changeset) do
    case Ash.Changeset.fetch_change(changeset, :display_name) do
      {:ok, name} when is_binary(name) -> String.replace(name, ~r/[^A-Za-z0-9_.-]+/, "-")
      _ -> nil
    end
  end
end
