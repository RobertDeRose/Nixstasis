defmodule NixstasisWeb.CommandPolicyLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Domain
  alias NixstasisWeb.Permissions

  @impl true
  def mount(_params, session, socket) do
    can_view = Permissions.can_view_command_policy_details?(session)
    can_manage = Permissions.can_manage_command_policies?(session)

    socket =
      socket
      |> assign(:page_title, "Command Policies")
      |> assign(:can_view, can_view)
      |> assign(:can_manage, can_manage)
      |> assign(:session, session)
      |> assign(:entries, [])
      |> assign(:categories, [])
      |> assign(:current_params, %{})
      |> assign(:selected_assignment_entry_id, nil)
      |> assign(:entry, nil)

    if can_view do
      {:ok, socket}
    else
      {:ok, socket |> put_flash(:error, "Not authorized") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    if socket.assigns.can_view do
      categories = Domain.list_command_allowlist_categories() |> elem(1)
      entries = inventory_rows(params, categories)

      socket =
        socket
        |> assign(:page_title, title(socket.assigns.live_action))
        |> assign(:categories, categories)
        |> assign(:entries, entries)
        |> assign(:current_params, params)
        |> assign(:selected_assignment_entry_id, params["assign_entry_id"])
        |> assign(:entry, current_entry(socket.assigns.live_action, params, entries))

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filter", params, socket) do
    merged =
      socket.assigns.current_params
      |> Map.merge(Map.take(params, ["search", "category_id", "status", "assigned"]))
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    {:noreply, push_patch(socket, to: ~p"/scripts/command-policies?#{merged}")}
  end

  def handle_event("clear_filters", _params, socket) do
    keep = Map.take(socket.assigns.current_params, ["assign_entry_id"])
    {:noreply, push_patch(socket, to: ~p"/scripts/command-policies?#{keep}")}
  end

  def handle_event("archive_entry", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      with %{entry: entry} <- Enum.find(socket.assigns.entries, &(&1.entry.id == id)),
           {:ok, _} <-
             Domain.update_command_allowlist_entry(entry, %{
               archived_at: DateTime.utc_now() |> DateTime.truncate(:second),
               current_version: entry.current_version + 1
             }) do
        {:noreply, put_flash(socket, :info, "Command entry disabled")}
      else
        _ -> {:noreply, put_flash(socket, :error, "Failed to disable command entry")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end

  def handle_event("duplicate_entry", %{"id" => id}, socket) do
    if socket.assigns.can_manage do
      with %{entry: entry, categories: categories} <- Enum.find(socket.assigns.entries, &(&1.entry.id == id)),
           name <- duplicate_name(entry.name),
           {:ok, duplicate} <-
             Domain.create_command_allowlist_entry(%{
               name: name,
               description: entry.description,
               command_path: entry.command_path
             }),
           :ok <- attach_categories(duplicate.id, categories) do
        {:noreply,
         socket
         |> put_flash(:info, "Command entry duplicated")
         |> push_patch(to: ~p"/scripts/command-policies/#{duplicate.id}/edit?#{socket.assigns.current_params}")}
      else
        _ -> {:noreply, put_flash(socket, :error, "Failed to duplicate command entry")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end

  def handle_event("assign_shortcut", %{"id" => id}, socket) do
    params = Map.put(socket.assigns.current_params, "assign_entry_id", id)
    {:noreply, push_patch(socket, to: ~p"/scripts/command-policies?#{params}")}
  end

  @impl true
  def handle_info({NixstasisWeb.CommandPolicyLive.FormComponent, {:saved, _entry}}, socket) do
    {:noreply, put_flash(socket, :info, "Command entry saved")}
  end

  defp current_entry(:edit, %{"id" => id}, rows) do
    case Enum.find(rows, &(&1.entry.id == id)) do
      %{entry: entry} -> entry
      _ -> nil
    end
  end

  defp current_entry(:new, _params, _rows), do: %{id: nil}
  defp current_entry(_, _params, _rows), do: nil

  defp title(:new), do: "New Command Entry"
  defp title(:edit), do: "Edit Command Entry"
  defp title(_), do: "Command Policies"

  defp inventory_rows(params, categories) do
    entries = Domain.list_command_allowlist_entries() |> elem(1)
    entry_categories = Domain.list_command_allowlist_entry_categories() |> elem(1)
    sources = Domain.list_command_policy_assignment_sources() |> elem(1)

    category_map = Map.new(categories, &{&1.id, &1})

    rows =
      Enum.map(entries, fn entry ->
        category_ids =
          entry_categories
          |> Enum.filter(&(&1.command_entry_id == entry.id))
          |> Enum.map(& &1.category_id)

        %{
          entry: entry,
          categories: Enum.map(category_ids, &category_map[&1]) |> Enum.reject(&is_nil/1),
          assignment_count: Enum.count(sources, &(&1.source_kind == "command_entry" and &1.source_id == entry.id))
        }
      end)

    rows
    |> filter_rows(params)
    |> Enum.sort_by(&{&1.entry.archived_at != nil, &1.entry.name})
  end

  defp filter_rows(rows, params) do
    rows
    |> maybe_filter_search(params["search"])
    |> maybe_filter_category(params["category_id"])
    |> maybe_filter_status(params["status"])
    |> maybe_filter_assigned(params["assigned"])
  end

  defp maybe_filter_search(rows, nil), do: rows
  defp maybe_filter_search(rows, ""), do: rows

  defp maybe_filter_search(rows, search) do
    needle = String.downcase(String.trim(search))

    Enum.filter(rows, fn %{entry: entry} ->
      Enum.any?(
        [entry.name, entry.command_path, entry.description],
        &String.contains?(String.downcase(&1 || ""), needle)
      )
    end)
  end

  defp maybe_filter_category(rows, nil), do: rows
  defp maybe_filter_category(rows, ""), do: rows

  defp maybe_filter_category(rows, category_id),
    do: Enum.filter(rows, &Enum.any?(&1.categories, fn category -> category.id == category_id end))

  defp maybe_filter_status(rows, "archived"), do: Enum.filter(rows, &(&1.entry.archived_at != nil))
  defp maybe_filter_status(rows, "enabled"), do: Enum.filter(rows, &is_nil(&1.entry.archived_at))
  defp maybe_filter_status(rows, _), do: rows

  defp maybe_filter_assigned(rows, "assigned"), do: Enum.filter(rows, &(&1.assignment_count > 0))
  defp maybe_filter_assigned(rows, "unassigned"), do: Enum.filter(rows, &(&1.assignment_count == 0))
  defp maybe_filter_assigned(rows, _), do: rows

  defp duplicate_name(name), do: name <> "-copy"

  defp attach_categories(entry_id, categories) do
    Enum.reduce_while(categories, :ok, fn category, :ok ->
      case Domain.create_command_allowlist_entry_category(%{command_entry_id: entry_id, category_id: category.id}) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :category_attach_failed}}
      end
    end)
  end
end
