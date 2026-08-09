defmodule NixstasisWeb.CommandPolicyLive.Index do
  use NixstasisWeb, :live_view

  import Ecto.Query, only: [from: 2]
  require Ash.Query

  alias Nixstasis.CommandAllowlists.Audit
  alias Nixstasis.CommandAllowlists.Category
  alias Nixstasis.CommandAllowlists.CommandEntry
  alias Nixstasis.CommandAllowlists.CommandEntryCategory
  alias Nixstasis.CommandAllowlists.DevicePolicyAssignment
  alias Nixstasis.CommandAllowlists.DevicePolicyAssignmentSource
  alias Nixstasis.CommandAllowlists.PolicyDeliveryResult
  alias Nixstasis.CommandCatalog.CatalogCommand
  alias Nixstasis.CommandCatalog.Category, as: CatalogCategory
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Repo
  alias NixstasisWeb.Permissions

  @collection_limit 250
  @entry_category_limit 2_500

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
      categories = list_command_policy_categories()
      catalog_categories = list_catalog_categories()
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

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, preview_error_message(reason))}
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

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, preview_error_message(reason))}
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
    categories = list_command_policy_categories()
    catalog_categories = list_catalog_categories()
    catalog_commands = catalog_command_options(params)
    entries = inventory_rows(params, categories)

    socket
    |> assign(:categories, categories)
    |> assign(:catalog_categories, catalog_categories)
    |> assign(:catalog_commands, catalog_commands)
    |> assign(:entries, entries)
    |> assign(:devices, approved_devices(socket.assigns.session))
    |> assign_scoped_assignments()
    |> assign(:entry, current_entry(socket.assigns.live_action, params, entries))
    |> assign(:category, current_category(socket.assigns.live_action, params, categories))
  end

  defp current_entry(:edit, %{"id" => id}, rows) do
    case Enum.find(rows, &(&1.entry.id == id)) do
      %{entry: entry} -> entry
      _ -> fetch_command_entry(id)
    end
  end

  defp current_entry(:new, _params, _rows), do: %{id: nil}
  defp current_entry(_, _params, _rows), do: nil

  defp fetch_command_entry(id) do
    CommandEntry
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.limit(1)
    |> Ash.Query.select([:id, :name, :command_path, :description, :archived_at, :updated_at, :current_version])
    |> Ash.read!(domain: Domain)
    |> List.first()
  end

  defp title(:new), do: "New Command Entry"
  defp title(:edit), do: "Edit Command Entry"
  defp title(:new_category), do: "New Category"
  defp title(:edit_category), do: "Edit Category"
  defp title(_), do: "Command Policies"

  defp list_command_policy_categories do
    Category
    |> Ash.Query.sort(slug: :asc)
    |> Ash.Query.limit(@collection_limit)
    |> Ash.Query.select([:id, :slug, :display_name, :description])
    |> Ash.read!(domain: Domain)
  end

  defp list_catalog_categories do
    CatalogCategory
    |> Ash.Query.sort(slug: :asc)
    |> Ash.Query.limit(@collection_limit)
    |> Ash.Query.select([:id, :slug, :display_name, :description])
    |> Ash.read!(domain: Domain)
  end

  defp list_catalog_commands(params) do
    CatalogCommand
    |> Ash.Query.filter(active == true)
    |> maybe_filter_catalog_search_query(params["search"])
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.limit(@collection_limit)
    |> Ash.Query.select([:id, :name, :display_name, :description, :category_slugs, :active])
    |> Ash.read!(domain: Domain)
  end

  defp maybe_filter_catalog_search_query(query, search) when search in [nil, ""], do: query

  defp maybe_filter_catalog_search_query(query, search) do
    needle = String.downcase(String.trim(search))

    if needle == "" do
      query
    else
      Ash.Query.filter(
        query,
        contains(string_downcase(name), ^needle) or
          contains(string_downcase(display_name), ^needle) or
          contains(string_downcase(description), ^needle) or
          contains(string_downcase(string_join(category_slugs, " ")), ^needle)
      )
    end
  end

  defp selected_ids(nil), do: []
  defp selected_ids(""), do: []
  defp selected_ids(id) when is_binary(id), do: [id]

  defp approved_devices(session) do
    authorized_device_ids =
      session
      |> Permissions.device_permissions()
      |> Permissions.authorized_device_ids()

    Device
    |> Ash.Query.filter(approval_status == :approved)
    |> maybe_filter_authorized_devices(authorized_device_ids)
    |> Ash.Query.sort(product_name: :asc, mac_address: :asc)
    |> Ash.Query.limit(@collection_limit)
    |> Ash.Query.select([:id, :mac_address, :product_name, :approval_status])
    |> Ash.read!(domain: Domain)
    |> Enum.filter(&Permissions.can_assign_command_policy_to_device?(session, &1))
  end

  defp maybe_filter_authorized_devices(query, nil), do: query
  defp maybe_filter_authorized_devices(query, ids), do: Ash.Query.filter(query, id in ^MapSet.to_list(ids))

  defp assign_scoped_assignments(socket) do
    allowed_device_ids = Enum.map(socket.assigns.devices, & &1.id)

    assignments =
      DevicePolicyAssignment
      |> Ash.Query.filter(device_id in ^allowed_device_ids)
      |> Ash.Query.sort(inserted_at: :desc)
      |> Ash.Query.limit(@collection_limit)
      |> Ash.Query.select([
        :id,
        :device_id,
        :status,
        :revision,
        :drift_warning,
        :resolved_policy,
        :inserted_at
      ])
      |> Ash.read!(domain: Domain)

    assign(socket, :assignments, assignments)
    |> assign(:delivery_results, delivery_results_for_assignments(assignments))
  end

  defp delivery_results_for_assignments([]), do: %{}

  defp delivery_results_for_assignments(assignments) do
    assignments
    |> Enum.map(& &1.id)
    |> then(fn ids ->
      PolicyDeliveryResult
      |> Ash.Query.filter(assignment_id in ^ids)
      |> Ash.Query.distinct(:assignment_id)
      |> Ash.Query.distinct_sort(assignment_id: :asc, reported_at: :desc, id: :desc)
      |> Ash.Query.limit(length(ids))
      |> Ash.Query.select([:id, :assignment_id, :status, :failure_reason, :reported_at])
      |> Ash.read!(domain: Domain)
      |> Enum.group_by(& &1.assignment_id)
      |> Map.new(fn {assignment_id, results} -> {assignment_id, List.first(results)} end)
    end)
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

  defp list_param(values) when is_list(values), do: values
  defp list_param(value) when is_binary(value) and value != "", do: [value]
  defp list_param(nil), do: []
  defp list_param(value), do: [value]

  defp scope_assignment_attrs(attrs, socket) do
    allowed_device_ids = MapSet.new(Enum.map(socket.assigns.devices, & &1.id))

    Map.update!(attrs, "device_ids", &Enum.filter(&1, fn id -> MapSet.member?(allowed_device_ids, id) end))
  end

  defp build_assignment_preview(socket, attrs) do
    requested_attrs = attrs
    attrs = scope_assignment_attrs(attrs, socket)

    with {:ok, bounds} <- Domain.preflight_command_policy(attrs),
         scoped_attrs =
           attrs
           |> Map.put("entry_ids", bounds.manual.active_entry_ids)
           |> Map.put("category_ids", bounds.manual.valid_category_ids)
           |> Map.put("catalog_command_ids", bounds.catalog.direct_command_ids)
           |> Map.put("catalog_category_ids", bounds.catalog.valid_category_ids),
         {:ok, manual_preview} <-
           Domain.preview_command_policy(%{
             entry_ids: scoped_attrs["entry_ids"],
             category_ids: scoped_attrs["category_ids"]
           }),
         {:ok, catalog_preview} <-
           Domain.preview_catalog_command_compatibility(%{
             device_ids: scoped_attrs["device_ids"],
             catalog_command_ids: scoped_attrs["catalog_command_ids"],
             catalog_category_ids: scoped_attrs["catalog_category_ids"]
           }) do
      preview =
        manual_preview
        |> Map.put(:device_ids, scoped_attrs["device_ids"])
        |> Map.put(:catalog, catalog_preview)
        |> Map.put(
          :catalog_blockers,
          catalog_blockers(catalog_preview, manual_preview.commands) ++
            dropped_catalog_blockers(requested_attrs, catalog_preview)
        )
        |> Map.put(:catalog_commands, catalog_commands_for_devices(catalog_preview))

      {:ok, scoped_attrs, preview}
    end
  end

  defp dropped_catalog_blockers(requested_attrs, catalog_preview) do
    requested_command_ids = MapSet.new(requested_attrs["catalog_command_ids"])
    selected_command_ids = MapSet.new(catalog_preview.selected_catalog_command_ids)

    requested_command_ids
    |> MapSet.difference(selected_command_ids)
    |> Enum.map(fn id ->
      %{
        status: :catalog_command_unavailable,
        catalog_command_id: id,
        name: id
      }
    end)
  end

  defp preview_error_message({:command_policy_limit_exceeded, %{kind: :commands, limit: limit}}) do
    "Selection resolves to more than #{limit} commands; narrow the selected entries, categories, or catalog commands"
  end

  defp preview_error_message({:command_policy_limit_exceeded, %{kind: :source_rows, limit: limit}}) do
    "Selection contains more than #{limit} policy source rows; narrow the selected entries or categories"
  end

  defp preview_error_message({:invalid_manual_source, _details}) do
    "One or more selected manual entries or categories are no longer available; refresh and choose valid sources"
  end

  defp preview_error_message({:invalid_catalog_source, _details}) do
    "One or more selected catalog commands or categories are no longer available; refresh and choose valid sources"
  end

  defp preview_error_message(_reason), do: "Failed to preview assignment"

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
    revision =
      DevicePolicyAssignment
      |> Ash.Query.filter(device_id == ^device_id)
      |> Ash.Query.sort(revision: :desc)
      |> Ash.Query.limit(1)
      |> Ash.Query.select([:revision])
      |> Ash.read!(domain: Domain)
      |> List.first()
      |> case do
        nil -> 0
        assignment -> assignment.revision
      end

    revision + 1
  end

  defp latest_result(delivery_results, assignment_id), do: Map.get(delivery_results, assignment_id)

  defp current_category(:edit_category, %{"id" => id}, categories) do
    Enum.find(categories, &(&1.id == id)) || fetch_command_policy_category(id)
  end

  defp current_category(:new_category, _params, _categories), do: %{id: nil}
  defp current_category(_, _params, _categories), do: nil

  defp fetch_command_policy_category(id) do
    Category
    |> Ash.Query.filter(id == ^id)
    |> Ash.Query.limit(1)
    |> Ash.Query.select([:id, :slug, :display_name, :description])
    |> Ash.read!(domain: Domain)
    |> List.first()
  end

  defp catalog_command_options(params), do: list_catalog_commands(params)

  defp inventory_rows(params, categories) do
    entries = list_inventory_entries(params)
    entry_ids = Enum.map(entries, & &1.id)
    category_map = Map.new(categories, &{&1.id, &1})
    categories_by_entry = entry_categories_by_entry(entry_ids, category_map)
    assignment_counts = assignment_counts_by_entry(entry_ids)

    entries
    |> Enum.map(fn entry ->
      %{
        entry: entry,
        categories: Map.get(categories_by_entry, entry.id, []),
        assignment_count: Map.get(assignment_counts, entry.id, 0)
      }
    end)
  end

  defp list_inventory_entries(params) do
    CommandEntry
    |> maybe_filter_entry_search(params["search"])
    |> maybe_filter_entry_category(params["category_id"])
    |> maybe_filter_entry_status(params["status"])
    |> maybe_filter_entry_assigned(params["assigned"])
    |> Ash.Query.sort(archived_at: :asc, name: :asc)
    |> Ash.Query.limit(@collection_limit)
    |> Ash.Query.select([:id, :name, :command_path, :description, :archived_at, :updated_at, :current_version])
    |> Ash.read!(domain: Domain)
  end

  defp maybe_filter_entry_search(query, search) when search in [nil, ""], do: query

  defp maybe_filter_entry_search(query, search) do
    needle = String.downcase(String.trim(search))

    if needle == "" do
      query
    else
      Ash.Query.filter(
        query,
        contains(string_downcase(name), ^needle) or
          contains(string_downcase(command_path), ^needle) or
          contains(string_downcase(description), ^needle)
      )
    end
  end

  defp maybe_filter_entry_category(query, category_id) when category_id in [nil, ""], do: query

  defp maybe_filter_entry_category(query, category_id) do
    Ash.Query.filter(query, exists(entry_categories, category_id == ^category_id))
  end

  defp maybe_filter_entry_status(query, "archived"), do: Ash.Query.filter(query, not is_nil(archived_at))
  defp maybe_filter_entry_status(query, "enabled"), do: Ash.Query.filter(query, is_nil(archived_at))
  defp maybe_filter_entry_status(query, _status), do: query

  defp maybe_filter_entry_assigned(query, "assigned") do
    Ash.Query.filter(query, exists(assignment_sources))
  end

  defp maybe_filter_entry_assigned(query, "unassigned") do
    Ash.Query.filter(query, not exists(assignment_sources))
  end

  defp maybe_filter_entry_assigned(query, _assigned), do: query

  defp entry_categories_by_entry([], _category_map), do: %{}

  defp entry_categories_by_entry(entry_ids, category_map) do
    CommandEntryCategory
    |> Ash.Query.filter(command_entry_id in ^entry_ids)
    |> Ash.Query.sort(command_entry_id: :asc, category_id: :asc)
    |> Ash.Query.limit(@entry_category_limit)
    |> Ash.Query.select([:command_entry_id, :category_id])
    |> Ash.read!(domain: Domain)
    |> Enum.group_by(& &1.command_entry_id, fn join -> Map.get(category_map, join.category_id) end)
    |> Map.new(fn {entry_id, values} -> {entry_id, Enum.reject(values, &is_nil/1)} end)
  end

  defp assignment_counts_by_entry([]), do: %{}

  defp assignment_counts_by_entry(entry_ids) do
    binary_entry_ids = Enum.map(entry_ids, &Ecto.UUID.dump!/1)

    Repo.all(
      from source in "command_policy_assignment_sources",
        where: source.source_kind == "command_entry" and source.source_id in ^binary_entry_ids,
        group_by: source.source_id,
        select: {source.source_id, count(source.id)}
    )
    |> Map.new(fn {source_id, count} -> {Ecto.UUID.cast!(source_id), count} end)
  end

  defp duplicate_name(name), do: name <> "-copy"

  defp category_entry_count(category_id) do
    CommandEntryCategory
    |> Ash.Query.filter(category_id == ^category_id)
    |> Ash.count!(domain: Domain)
  end

  defp category_assignment_count(category_id) do
    DevicePolicyAssignmentSource
    |> Ash.Query.filter(source_kind == "category" and source_id == ^category_id)
    |> Ash.count!(domain: Domain)
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
