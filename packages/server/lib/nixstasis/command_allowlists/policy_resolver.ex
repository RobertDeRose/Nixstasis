defmodule Nixstasis.CommandAllowlists.PolicyResolver do
  @moduledoc """
  Resolves selected command entries/category tags into command policy previews.

  Resolution is deliberately scoped to the IDs supplied by the caller.  The
  count queries run before any source rows are materialized so oversized
  category expansions fail without producing a partial policy.
  """

  require Ash.Query

  alias Nixstasis.CommandAllowlists.CommandEntry
  alias Nixstasis.CommandAllowlists.CommandEntryCategory
  alias Nixstasis.CommandAllowlists.Category
  alias Nixstasis.Domain

  @command_limit 2_500
  @source_row_limit 10_000

  def preflight(attrs) when is_map(attrs) do
    {entry_ids, invalid_entry_ids} = normalized_ids(Map.get(attrs, :entry_ids, Map.get(attrs, "entry_ids", [])))

    {category_ids, invalid_category_ids} =
      normalized_ids(Map.get(attrs, :category_ids, Map.get(attrs, "category_ids", [])))

    with :ok <- validate_id_inputs(invalid_entry_ids, invalid_category_ids),
         {:ok, source_counts} <- source_counts(entry_ids, category_ids),
         :ok <- enforce_source_limit(source_counts),
         {:ok, command_count} <- resolved_command_count(entry_ids, category_ids),
         :ok <- enforce_command_limit(command_count) do
      {:ok,
       %{
         entry_ids: entry_ids,
         category_ids: category_ids,
         active_entry_ids: active_entry_ids(entry_ids),
         valid_category_ids: valid_category_ids(category_ids),
         source_row_count: source_counts.total,
         resolved_command_count: command_count
       }}
    end
  end

  def preview(attrs) when is_map(attrs) do
    current_commands = Map.get(attrs, :current_commands, Map.get(attrs, "current_commands", %{})) || %{}

    with {:ok, bounds} <- preflight(attrs),
         {:ok, selected_entries} <- selected_entries(bounds.entry_ids),
         {:ok, category_entries} <- category_entries(bounds.category_ids) do
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
         payload: %{"commands" => commands},
         source_row_count: bounds.source_row_count,
         resolved_command_count: bounds.resolved_command_count
       }}
    end
  end

  defp active_entry_ids([]), do: []

  defp active_entry_ids(entry_ids) do
    CommandEntry
    |> Ash.Query.filter(id in ^entry_ids and is_nil(archived_at))
    |> Ash.Query.select([:id])
    |> Ash.read!(domain: Domain)
    |> Enum.map(& &1.id)
  end

  defp valid_category_ids([]), do: []

  defp valid_category_ids(category_ids) do
    Category
    |> Ash.Query.filter(id in ^category_ids)
    |> Ash.Query.select([:id])
    |> Ash.read!(domain: Domain)
    |> Enum.map(& &1.id)
  end

  defp source_counts(entry_ids, category_ids) do
    selected_count =
      CommandEntry
      |> Ash.Query.filter(id in ^entry_ids and is_nil(archived_at))
      |> Ash.count!(domain: Domain)

    category_count =
      CommandEntryCategory
      |> Ash.Query.filter(category_id in ^category_ids and exists(command_entry, is_nil(archived_at)))
      |> Ash.count!(domain: Domain)

    {:ok,
     %{selected_entries: selected_count, category_memberships: category_count, total: selected_count + category_count}}
  end

  defp resolved_command_count(entry_ids, category_ids) do
    count =
      CommandEntry
      |> Ash.Query.filter(
        is_nil(archived_at) and
          (id in ^entry_ids or exists(entry_categories, category_id in ^category_ids))
      )
      |> Ash.Query.distinct(:name)
      |> Ash.count!(domain: Domain)

    {:ok, count}
  end

  defp enforce_source_limit(%{total: count}) when count > @source_row_limit,
    do: limit_error(:source_rows, @source_row_limit, count)

  defp enforce_source_limit(_counts), do: :ok

  defp enforce_command_limit(count) when count > @command_limit,
    do: limit_error(:commands, @command_limit, count)

  defp enforce_command_limit(_count), do: :ok

  defp limit_error(kind, limit, actual),
    do: {:error, {:command_policy_limit_exceeded, %{kind: kind, limit: limit, actual: actual}}}

  defp selected_entries([]), do: {:ok, []}

  defp selected_entries(entry_ids) do
    entries =
      CommandEntry
      |> Ash.Query.filter(id in ^entry_ids and is_nil(archived_at))
      |> Ash.Query.select([:id, :name, :command_path, :current_version])
      |> Ash.read!(domain: Domain)

    {:ok, Enum.map(entries, &source(&1, :command_entry, &1.id))}
  end

  defp category_entries([]), do: {:ok, []}

  defp category_entries(category_ids) do
    joins =
      CommandEntryCategory
      |> Ash.Query.filter(category_id in ^category_ids and exists(command_entry, is_nil(archived_at)))
      |> Ash.Query.select([:command_entry_id, :category_id])
      |> Ash.read!(domain: Domain)

    entry_ids = joins |> Enum.map(& &1.command_entry_id) |> Enum.uniq()

    entries_by_id =
      CommandEntry
      |> Ash.Query.filter(id in ^entry_ids and is_nil(archived_at))
      |> Ash.Query.select([:id, :name, :command_path, :current_version])
      |> Ash.read!(domain: Domain)
      |> Map.new(&{&1.id, &1})

    {:ok,
     Enum.flat_map(joins, fn join ->
       case Map.get(entries_by_id, join.command_entry_id) do
         nil -> []
         entry -> [source(entry, :category, join.category_id)]
       end
     end)}
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

  defp normalized_ids(ids) when is_list(ids) do
    {valid, invalid} =
      Enum.reduce(ids, {[], []}, fn id, {valid, invalid} ->
        case Ecto.UUID.cast(id) do
          {:ok, uuid} -> {[uuid | valid], invalid}
          :error -> {valid, [id | invalid]}
        end
      end)

    {Enum.uniq(valid), Enum.uniq(invalid)}
  end

  defp normalized_ids(_), do: {[], []}

  defp validate_id_inputs([], []), do: :ok

  defp validate_id_inputs(invalid_entry_ids, invalid_category_ids) do
    {:error, {:invalid_manual_source, %{entry_ids: invalid_entry_ids, category_ids: invalid_category_ids}}}
  end
end
