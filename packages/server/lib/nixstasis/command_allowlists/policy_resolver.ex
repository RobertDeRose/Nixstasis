defmodule Nixstasis.CommandAllowlists.PolicyResolver do
  @moduledoc """
  Resolves selected command entries/category tags into command policy previews.
  """

  alias Nixstasis.Domain

  def preview(attrs) when is_map(attrs) do
    entry_ids = normalize_ids(Map.get(attrs, :entry_ids, Map.get(attrs, "entry_ids", [])))
    category_ids = normalize_ids(Map.get(attrs, :category_ids, Map.get(attrs, "category_ids", [])))
    current_commands = Map.get(attrs, :current_commands, Map.get(attrs, "current_commands", %{})) || %{}

    with {:ok, selected_entries} <- selected_entries(entry_ids),
         {:ok, category_entries} <- category_entries(category_ids) do
      sources = selected_entries ++ category_entries
      grouped = Enum.group_by(sources, & &1.name)
      conflicts = conflicts(grouped)

      commands =
        grouped
        |> Enum.reject(fn {_name, entries} -> conflicting?(entries) end)
        |> Map.new(fn {name, [entry | _]} -> {name, entry.command_path} end)

      {:ok,
       %{
         commands: commands,
         provenance: provenance(grouped),
         conflicts: conflicts,
         diff: diff(current_commands, commands),
         payload: %{"commands" => commands}
       }}
    end
  end

  defp selected_entries([]), do: {:ok, []}

  defp selected_entries(entry_ids) do
    with {:ok, entries} <- Domain.list_command_allowlist_entries() do
      {:ok,
       entries
       |> Enum.filter(&(&1.id in entry_ids and is_nil(&1.archived_at)))
       |> Enum.map(&source(&1, :command_entry, &1.id))}
    end
  end

  defp category_entries([]), do: {:ok, []}

  defp category_entries(category_ids) do
    with {:ok, joins} <- Domain.list_command_allowlist_entry_categories(),
         {:ok, entries} <- Domain.list_command_allowlist_entries() do
      entries_by_id = Map.new(entries, &{&1.id, &1})

      {:ok,
       joins
       |> Enum.filter(&(&1.category_id in category_ids))
       |> Enum.flat_map(fn join ->
         case Map.get(entries_by_id, join.command_entry_id) do
           %{archived_at: nil} = entry -> [source(entry, :category, join.category_id)]
           _ -> []
         end
       end)}
    end
  end

  defp source(entry, source_kind, source_id) do
    %{
      id: entry.id,
      name: entry.name,
      command_path: entry.command_path,
      version: entry.current_version,
      source_kind: source_kind,
      source_id: source_id
    }
  end

  defp provenance(grouped) do
    Map.new(grouped, fn {name, entries} ->
      {name, Enum.map(entries, &Map.take(&1, [:id, :command_path, :version, :source_kind, :source_id]))}
    end)
  end

  defp conflicts(grouped) do
    grouped
    |> Enum.filter(fn {_name, entries} -> conflicting?(entries) end)
    |> Enum.map(fn {name, entries} ->
      %{name: name, paths: entries |> Enum.map(& &1.command_path) |> Enum.uniq() |> Enum.sort()}
    end)
  end

  defp conflicting?(entries), do: entries |> Enum.map(& &1.command_path) |> Enum.uniq() |> length() > 1

  defp diff(current, next) do
    %{
      added: Map.drop(next, Map.keys(current)),
      removed: Map.drop(current, Map.keys(next)),
      unchanged: Map.take(next, unchanged_keys(current, next))
    }
  end

  defp unchanged_keys(current, next) do
    current
    |> Enum.filter(fn {name, path} -> Map.get(next, name) == path end)
    |> Enum.map(&elem(&1, 0))
  end

  defp normalize_ids(ids) when is_list(ids), do: Enum.filter(ids, &is_binary/1)
  defp normalize_ids(_), do: []
end
