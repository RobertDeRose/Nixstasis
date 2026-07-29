defmodule NixstasisWeb.CommandPolicyLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.CommandAllowlists.Audit
  alias Nixstasis.Devices
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
      |> assign(:catalog_commands, [])
      |> assign(:catalog_categories, [])
      |> assign(:current_params, %{})
      |> assign(:selected_assignment_entry_id, nil)
      |> assign(:entry, nil)
      |> assign(:category, nil)

    if can_view do
      if connected?(socket), do: Process.send_after(self(), :refresh_command_policies, 15_000)
      {:ok, socket}
    else
      {:ok, socket |> put_flash(:error, "Not authorized") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    if socket.assigns.can_view do
      categories = Domain.list_command_allowlist_categories() |> elem(1)
      catalog_categories = Domain.list_command_catalog_categories() |> elem(1)
      catalog_commands = catalog_command_options(params)
      entries = inventory_rows(params, categories)

      socket =
        socket
        |> assign(:page_title, title(socket.assigns.live_action))
        |> assign(:categories, categories)
        |> assign(:catalog_categories, catalog_categories)
        |> assign(:catalog_commands, catalog_commands)
        |> assign(:entries, entries)
        |> assign(:current_params, params)
        |> assign(:selected_assignment_entry_id, params["assign_entry_id"])
        |> assign(:selected_assignment_category_id, params["assign_category_id"])
        |> assign(:devices, approved_devices(socket.assigns.session))
        |> assign_scoped_assignments()
        |> assign(:delivery_results, Domain.list_command_policy_delivery_results() |> elem(1))
        |> assign(:assignment_form, %{
          "device_ids" => [],
          "entry_ids" => selected_ids(params["assign_entry_id"]),
          "category_ids" => selected_ids(params["assign_category_id"]),
          "catalog_command_ids" => [],
          "catalog_category_ids" => []
        })
        |> assign(:assignment_preview, nil)
        |> assign(:entry, current_entry(socket.assigns.live_action, params, entries))
        |> assign(:category, current_category(socket.assigns.live_action, params, categories))

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

  def handle_event("refresh", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/scripts/command-policies?#{socket.assigns.current_params}")}
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
        Audit.emit(:command_entry_disabled, %{command_entry_id: entry.id, name: entry.name})
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

  def handle_event("assign_category_shortcut", %{"id" => id}, socket) do
    params = Map.put(socket.assigns.current_params, "assign_category_id", id)
    {:noreply, push_patch(socket, to: ~p"/scripts/command-policies?#{params}")}
  end

  def handle_event("preview_assignment", %{"assignment" => attrs}, socket) do
    attrs = normalize_assignment_attrs(attrs)

    case build_assignment_preview(socket, attrs) do
      {:ok, scoped_attrs, preview} ->
        {:noreply, assign(socket, assignment_form: scoped_attrs, assignment_preview: preview)}

      _ ->
        {:noreply, put_flash(socket, :error, "Failed to preview assignment")}
    end
  end

  def handle_event("confirm_assignment", _params, socket) do
    form = socket.assigns.assignment_form
    preview = socket.assigns.assignment_preview

    cond do
      not socket.assigns.can_manage ->
        {:noreply, put_flash(socket, :error, "Not authorized")}

      is_nil(preview) ->
        {:noreply, put_flash(socket, :error, "Preview before confirming assignment")}

      true ->
        case build_assignment_preview(socket, form) do
          {:ok, scoped_form, current_preview}
          when current_preview.conflicts == [] and current_preview.catalog_blockers == [] ->
            {ok_count, error_count} = queue_assignments(socket, scoped_form, current_preview)

            {:noreply,
             socket
             |> put_flash(:info, "Queued #{ok_count} assignment(s), #{error_count} failed")
             |> push_patch(to: ~p"/scripts/command-policies?#{socket.assigns.current_params}")}

          {:ok, scoped_form, current_preview} ->
            {:noreply,
             socket
             |> assign(assignment_form: scoped_form, assignment_preview: current_preview)
             |> put_flash(:error, "Preview must be conflict-free and catalog-compatible before assignment")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to refresh assignment preview")}
        end
    end
  end

  def handle_event("retry_assignment", %{"id" => id}, socket) do
    assignment = scoped_assignment(socket, id)

    case assignment && Devices.queue_command_policy_assignment(assignment) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Assignment resent")}
      _ -> {:noreply, put_flash(socket, :error, "Failed to resend assignment")}
    end
  end

  def handle_event("revoke_all", %{"device-id" => device_id}, socket) do
    if Enum.any?(socket.assigns.devices, &(&1.id == device_id)) do
      case queue_revoke_all(device_id) do
        {:ok, _} -> {:noreply, put_flash(socket, :info, "Revoke-all policy queued")}
        _ -> {:noreply, put_flash(socket, :error, "Failed to queue revoke-all policy")}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end

  def handle_event("toggle_drift_warning", %{"id" => id}, socket) do
    with assignment when not is_nil(assignment) <- scoped_assignment(socket, id),
         {:ok, _} <-
           Ash.update(Ash.Changeset.for_update(assignment, :update, %{drift_warning: !assignment.drift_warning}),
             domain: Domain
           ) do
      {:noreply, push_patch(socket, to: ~p"/scripts/command-policies?#{socket.assigns.current_params}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Failed to update drift warning")}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Enum.find(socket.assigns.categories, &(&1.id == id))
    active_assignment_count = category_assignment_count(id)

    cond do
      not socket.assigns.can_manage ->
        {:noreply, put_flash(socket, :error, "Not authorized")}

      active_assignment_count > 0 ->
        {:noreply, put_flash(socket, :error, "Category has active assignments")}

      category ->
        remove_category_tags(id)

        case Domain.destroy_command_allowlist_category(category) do
          {:ok, _} ->
            Audit.emit(:category_deleted, %{category_id: id, slug: category.slug})
            {:noreply, put_flash(socket, :info, "Category deleted")}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to delete category")}
        end

      true ->
        {:noreply, put_flash(socket, :error, "Category not found")}
    end
  end

  @impl true
  def handle_info({NixstasisWeb.CommandPolicyLive.FormComponent, {:saved, _entry}}, socket) do
    {:noreply, put_flash(socket, :info, "Command entry saved")}
  end

  def handle_info({NixstasisWeb.CommandPolicyLive.CategoryFormComponent, {:category_saved, _category}}, socket) do
    {:noreply, put_flash(socket, :info, "Category saved")}
  end

  def handle_info(:refresh_command_policies, socket) do
    Process.send_after(self(), :refresh_command_policies, 15_000)
    {:noreply, refresh_policy_assigns(socket)}
  end

  defp refresh_policy_assigns(socket) do
    params = socket.assigns.current_params
    categories = Domain.list_command_allowlist_categories() |> elem(1)
    catalog_categories = Domain.list_command_catalog_categories() |> elem(1)
    catalog_commands = catalog_command_options(params)
    entries = inventory_rows(params, categories)

    socket
    |> assign(:categories, categories)
    |> assign(:catalog_categories, catalog_categories)
    |> assign(:catalog_commands, catalog_commands)
    |> assign(:entries, entries)
    |> assign(:devices, approved_devices(socket.assigns.session))
    |> assign_scoped_assignments()
    |> assign(:delivery_results, Domain.list_command_policy_delivery_results() |> elem(1))
    |> assign(:entry, current_entry(socket.assigns.live_action, params, entries))
    |> assign(:category, current_category(socket.assigns.live_action, params, categories))
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
  defp title(:new_category), do: "New Category"
  defp title(:edit_category), do: "Edit Category"
  defp title(_), do: "Command Policies"

  defp selected_ids(nil), do: []
  defp selected_ids(""), do: []
  defp selected_ids(id) when is_binary(id), do: [id]

  defp approved_devices(session) do
    Domain.list_devices()
    |> elem(1)
    |> Enum.filter(&Permissions.can_assign_command_policy_to_device?(session, &1))
  end

  defp assign_scoped_assignments(socket) do
    allowed_device_ids = MapSet.new(Enum.map(socket.assigns.devices, & &1.id))

    assignments =
      Domain.list_command_policy_assignments()
      |> elem(1)
      |> Enum.filter(&MapSet.member?(allowed_device_ids, &1.device_id))

    assign(socket, :assignments, assignments)
  end

  defp scoped_assignment(socket, assignment_id) do
    Enum.find(socket.assigns.assignments, &(&1.id == assignment_id))
  end

  defp normalize_assignment_attrs(attrs) do
    %{
      "device_ids" => list_param(attrs["device_ids"]),
      "entry_ids" => list_param(attrs["entry_ids"]),
      "category_ids" => list_param(attrs["category_ids"]),
      "catalog_command_ids" => list_param(attrs["catalog_command_ids"]),
      "catalog_category_ids" => list_param(attrs["catalog_category_ids"])
    }
  end

  defp list_param(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp list_param(value) when is_binary(value) and value != "", do: [value]
  defp list_param(_), do: []

  defp scope_assignment_attrs(attrs, socket) do
    allowed_device_ids = MapSet.new(Enum.map(socket.assigns.devices, & &1.id))
    active_catalog_command_ids = MapSet.new(Enum.map(all_active_catalog_commands(), & &1.id))
    catalog_category_ids = MapSet.new(Enum.map(socket.assigns.catalog_categories, & &1.id))

    attrs
    |> Map.update!("device_ids", &Enum.filter(&1, fn id -> MapSet.member?(allowed_device_ids, id) end))
    |> Map.update!("catalog_command_ids", &Enum.filter(&1, fn id -> MapSet.member?(active_catalog_command_ids, id) end))
    |> Map.update!("catalog_category_ids", &Enum.filter(&1, fn id -> MapSet.member?(catalog_category_ids, id) end))
  end

  defp build_assignment_preview(socket, attrs) do
    requested_attrs = attrs
    attrs = scope_assignment_attrs(attrs, socket)

    with {:ok, manual_preview} <-
           Domain.preview_command_policy(%{entry_ids: attrs["entry_ids"], category_ids: attrs["category_ids"]}),
         {:ok, catalog_preview} <-
           Domain.preview_catalog_command_compatibility(%{
             device_ids: attrs["device_ids"],
             catalog_command_ids: selected_catalog_command_ids(socket, attrs)
           }) do
      preview =
        manual_preview
        |> Map.put(:device_ids, attrs["device_ids"])
        |> Map.put(:catalog, catalog_preview)
        |> Map.put(
          :catalog_blockers,
          catalog_blockers(catalog_preview, manual_preview.commands) ++ dropped_catalog_blockers(requested_attrs, attrs)
        )
        |> Map.put(:catalog_commands, catalog_commands_for_devices(catalog_preview))

      {:ok, attrs, preview}
    end
  end

  defp dropped_catalog_blockers(requested_attrs, scoped_attrs) do
    requested_command_ids = MapSet.new(requested_attrs["catalog_command_ids"])
    scoped_command_ids = MapSet.new(scoped_attrs["catalog_command_ids"])

    requested_command_ids
    |> MapSet.difference(scoped_command_ids)
    |> Enum.map(fn id ->
      %{
        status: :catalog_command_unavailable,
        catalog_command_id: id,
        name: id
      }
    end)
  end

  defp selected_catalog_command_ids(socket, attrs) do
    selected_category_ids = MapSet.new(attrs["catalog_category_ids"])

    selected_category_slugs =
      socket.assigns.catalog_categories
      |> Enum.filter(&MapSet.member?(selected_category_ids, &1.id))
      |> MapSet.new(& &1.slug)

    from_categories =
      all_active_catalog_commands()
      |> Enum.filter(fn command -> Enum.any?(command.category_slugs, &MapSet.member?(selected_category_slugs, &1)) end)
      |> Enum.map(& &1.id)

    (attrs["catalog_command_ids"] ++ from_categories)
    |> Enum.uniq()
  end

  defp catalog_blockers(catalog_preview, manual_commands) do
    catalog_preview.devices
    |> Enum.flat_map(fn {device_id, device_preview} ->
      status_blockers =
        device_preview.commands
        |> Enum.reject(fn {_name, result} -> result.status == :command_path_resolved end)
        |> Enum.map(fn {name, result} -> Map.put(result, :device_id, device_id) |> Map.put(:name, name) end)

      path_blockers =
        device_preview.commands
        |> Enum.filter(fn {_name, result} -> result.status == :command_path_resolved end)
        |> Enum.filter(fn {name, result} -> Map.get(manual_commands, name) not in [nil, result.command_path] end)
        |> Enum.map(fn {name, result} ->
          result
          |> Map.put(:status, :conflict)
          |> Map.put(:device_id, device_id)
          |> Map.put(:name, name)
          |> Map.put(:manual_path, Map.get(manual_commands, name))
        end)

      status_blockers ++ path_blockers
    end)
  end

  defp catalog_commands_for_devices(catalog_preview) do
    Map.new(catalog_preview.devices, fn {device_id, device_preview} ->
      commands =
        device_preview.commands
        |> Enum.filter(fn {_name, result} -> result.status == :command_path_resolved end)
        |> Map.new(fn {name, result} -> {name, result.command_path} end)

      {device_id, commands}
    end)
  end

  defp queue_assignments(socket, form, preview) do
    allowed_device_ids = MapSet.new(Enum.map(socket.assigns.devices, & &1.id))

    form["device_ids"]
    |> Enum.filter(&MapSet.member?(allowed_device_ids, &1))
    |> Enum.reduce({0, 0}, fn device_id, {ok_count, error_count} ->
      case queue_assignment(device_id, form, preview) do
        {:ok, _} -> {ok_count + 1, error_count}
        _ -> {ok_count, error_count + 1}
      end
    end)
  end

  defp queue_assignment(device_id, form, preview) do
    revision = next_revision(device_id)

    with {:ok, assignment} <-
           Domain.create_command_policy_assignment(%{
             device_id: device_id,
             revision: revision,
             version: "policy-#{revision}",
             status: :queued,
             resolved_policy: %{"commands" => resolved_commands_for_device(preview, device_id)},
             source_snapshot: %{
               entries: form["entry_ids"],
               categories: form["category_ids"],
               catalog_commands: selected_catalog_source_ids(preview, device_id),
               catalog_categories: form["catalog_category_ids"],
               catalog_version: preview.catalog.catalog_version,
               catalog_resolution: catalog_resolution_snapshot(preview, device_id)
             },
             queued_at: DateTime.utc_now() |> DateTime.truncate(:second)
           }),
         :ok <- create_assignment_sources(assignment, form, preview, device_id),
         {:ok, _command} <- Devices.queue_command_policy_assignment(assignment) do
      Audit.emit(:assignment_queued, %{assignment_id: assignment.id, device_id: device_id})
      {:ok, assignment}
    end
  end

  defp queue_revoke_all(device_id) do
    revision = next_revision(device_id)

    with {:ok, assignment} <-
           Domain.create_command_policy_assignment(%{
             device_id: device_id,
             revision: revision,
             version: "policy-#{revision}",
             status: :queued,
             resolved_policy: %{"commands" => %{}},
             source_snapshot: %{entries: [], categories: []},
             queued_at: DateTime.utc_now() |> DateTime.truncate(:second)
           }),
         {:ok, _command} <- Devices.queue_command_policy_assignment(assignment) do
      Audit.emit(:assignment_revoked, %{assignment_id: assignment.id, device_id: device_id})
      {:ok, assignment}
    end
  end

  defp resolved_commands_for_device(preview, device_id) do
    Map.merge(preview.commands, Map.get(preview.catalog_commands, device_id, %{}))
  end

  defp selected_catalog_source_ids(preview, device_id) do
    preview.catalog.devices
    |> Map.get(device_id, %{commands: %{}})
    |> Map.get(:commands)
    |> Enum.filter(fn {_name, result} -> result.status == :command_path_resolved end)
    |> Enum.map(fn {_name, result} -> result.catalog_command_id end)
  end

  defp create_assignment_sources(assignment, form, preview, device_id) do
    entry_sources = Enum.map(form["entry_ids"], &{:command_entry, &1})
    category_sources = Enum.map(form["category_ids"], &{:category, &1})
    catalog_command_sources = Enum.map(form["catalog_command_ids"], &{:catalog_command, &1})
    catalog_category_sources = Enum.map(form["catalog_category_ids"], &{:catalog_category, &1})

    Enum.reduce_while(
      entry_sources ++ category_sources ++ catalog_command_sources ++ catalog_category_sources,
      :ok,
      fn {kind, source_id}, :ok ->
        case Domain.create_command_policy_assignment_source(%{
               assignment_id: assignment.id,
               source_kind: Atom.to_string(kind),
               source_id: source_id,
               source_version: 1,
               source_snapshot: source_snapshot(kind, source_id, preview, device_id)
             }) do
          {:ok, _} -> {:cont, :ok}
          _ -> {:halt, {:error, :source_failed}}
        end
      end
    )
  end

  defp source_snapshot(kind, source_id, preview, device_id) when kind in [:catalog_command, :catalog_category] do
    snapshot = %{
      catalog_version: preview.catalog.catalog_version,
      device_id: device_id,
      resolved_commands: catalog_resolution_snapshot(preview, device_id)
    }

    case kind do
      :catalog_command -> Map.put(snapshot, :catalog_command_id, source_id)
      :catalog_category -> Map.put(snapshot, :catalog_category_id, source_id)
    end
  end

  defp source_snapshot(_kind, _source_id, _preview, _device_id), do: %{}

  defp catalog_resolution_snapshot(preview, device_id) do
    preview.catalog.devices
    |> Map.get(device_id, %{commands: %{}})
    |> Map.get(:commands)
    |> Enum.filter(fn {_name, result} -> result.status == :command_path_resolved end)
    |> Map.new(fn {name, result} ->
      {name,
       %{
         status: Atom.to_string(result.status),
         catalog_command_id: result.catalog_command_id,
         os_family: result.os_family,
         package_manager: result.package_manager,
         package_name: result.package_name,
         command_path: result.command_path
       }}
    end)
  end

  defp next_revision(device_id) do
    Domain.list_command_policy_assignments()
    |> elem(1)
    |> Enum.filter(&(&1.device_id == device_id))
    |> Enum.map(& &1.revision)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp assignment_results(assignment_id) do
    Domain.list_command_policy_delivery_results()
    |> elem(1)
    |> Enum.filter(&(&1.assignment_id == assignment_id))
  end

  defp latest_result(assignment_id),
    do: assignment_results(assignment_id) |> Enum.sort_by(& &1.reported_at, {:desc, DateTime}) |> List.first()

  defp current_category(:edit_category, %{"id" => id}, categories), do: Enum.find(categories, &(&1.id == id))
  defp current_category(:new_category, _params, _categories), do: %{id: nil}
  defp current_category(_, _params, _categories), do: nil

  defp all_active_catalog_commands do
    Domain.list_command_catalog_commands()
    |> elem(1)
    |> Enum.filter(& &1.active)
  end

  defp catalog_command_options(params) do
    all_active_catalog_commands()
    |> maybe_filter_catalog_search(params["search"])
    |> Enum.sort_by(& &1.name)
  end

  defp maybe_filter_catalog_search(commands, nil), do: commands
  defp maybe_filter_catalog_search(commands, ""), do: commands

  defp maybe_filter_catalog_search(commands, search) do
    needle = String.downcase(String.trim(search))

    Enum.filter(commands, fn command ->
      Enum.any?(
        [command.name, command.display_name, command.description, Enum.join(command.category_slugs, " ")],
        &String.contains?(String.downcase(&1 || ""), needle)
      )
    end)
  end

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

  defp category_entry_count(category_id) do
    Domain.list_command_allowlist_entry_categories()
    |> elem(1)
    |> Enum.count(&(&1.category_id == category_id))
  end

  defp category_assignment_count(category_id) do
    Domain.list_command_policy_assignment_sources()
    |> elem(1)
    |> Enum.count(&(&1.source_kind == "category" and &1.source_id == category_id))
  end

  defp remove_category_tags(category_id) do
    Domain.list_command_allowlist_entry_categories()
    |> elem(1)
    |> Enum.filter(&(&1.category_id == category_id))
    |> Enum.each(&Domain.destroy_command_allowlist_entry_category/1)
  end

  defp attach_categories(entry_id, categories) do
    Enum.reduce_while(categories, :ok, fn category, :ok ->
      case Domain.create_command_allowlist_entry_category(%{command_entry_id: entry_id, category_id: category.id}) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} -> {:halt, {:error, :category_attach_failed}}
      end
    end)
  end
end
