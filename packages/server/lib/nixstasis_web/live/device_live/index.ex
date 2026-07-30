defmodule NixstasisWeb.DeviceLive.Index do
  use NixstasisWeb, :live_view

  require Logger

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias NixstasisWeb.Permissions

  @sort_fields %{
    "account_number" => :account_number,
    "approval_status" => :approval_status,
    "inserted_at" => :inserted_at,
    "ipv4_address" => :ipv4_address,
    "last_seen_at" => :last_seen_at,
    "mac_address" => :mac_address,
    "product_name" => :product_name,
    "remote_access_requested" => :remote_access_requested
  }

  @sort_orders %{"asc" => :asc, "desc" => :desc}

  @impl true
  def mount(_params, session, socket) do
    permissions = Permissions.device_permissions(session)

    group_authorization =
      case Permissions.device_group_authorization(session) do
        {:ok, authorization} -> authorization
        {:error, _reason} -> nil
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")
    end

    {:ok,
     socket
     |> stream(:devices, [])
     |> assign(:selected_ids, [])
     |> assign(:selected_group_id, nil)
     |> assign(:active_filters, %{})
     |> assign(:device_permissions, permissions)
     |> assign(:group_authorization, group_authorization)
     |> assign(:device_groups, [])
     |> assign(:group_panel_open?, false)
     |> assign(:group_form, nil)
     |> assign(:show_archived_groups?, false)
     |> assign(:pending_group_delete, nil)
     |> assign(:groups_loading?, false)
     |> assign(:can_view_device_details?, Permissions.can_view_device_details?(permissions))
     # Placeholder for pagination if needed
     |> assign(:meta, %{page: 1, per_page: 50})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    if socket.assigns.can_view_device_details? do
      handle_authorized_params(params, socket)
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to view devices.")
       |> assign_unauthorized_devices_state()
       |> apply_action(socket.assigns.live_action, params)}
    end
  end

  defp handle_authorized_params(params, socket) do
    sort_by = Map.get(@sort_fields, params["sort_by"] || "inserted_at", :inserted_at)
    sort_order = Map.get(@sort_orders, params["sort_order"] || "desc", :desc)

    filter_approval_status =
      params["approval_status"]
      |> Devices.normalize_approval_status_filter()
      |> normalize_filter_atom()

    filter_connectivity_status =
      params["connectivity_status"]
      |> Devices.normalize_connectivity_status_filter()
      |> normalize_filter_atom()

    filter_product = normalize_blank(params["product"])
    filter_account_number = normalize_blank(params["account_number"])
    filter_ipv4_address = normalize_blank(params["ipv4_address"])
    search = params["search"]

    active_filters =
      %{
        "approval_status" => filter_approval_status,
        "connectivity_status" => filter_connectivity_status,
        "product" => filter_product,
        "account_number" => filter_account_number,
        "ipv4_address" => filter_ipv4_address
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    opts = [
      sort_by: sort_by,
      sort_order: sort_order,
      filter: %{
        approval_status: filter_approval_status,
        connectivity_status: filter_connectivity_status,
        product: filter_product,
        account_number: filter_account_number,
        ipv4_address: filter_ipv4_address
      },
      search: search
    ]

    devices = opts |> Devices.list_devices() |> filter_authorized_devices(socket.assigns.device_permissions)

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:filter_approval_status, filter_approval_status)
      |> assign(:filter_connectivity_status, filter_connectivity_status)
      |> assign(:filter_product, filter_product)
      |> assign(:filter_account_number, filter_account_number)
      |> assign(:filter_ipv4_address, filter_ipv4_address)
      |> assign(:active_filters, active_filters)
      |> assign(:search, search)
      |> then(fn s -> assign(s, :current_params, get_params(s.assigns)) end)
      |> assign(:total_count, length(devices))
      |> stream(:devices, devices, reset: true)
      |> refresh_device_groups()

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    if Permissions.can_create_devices?(socket.assigns.device_permissions) do
      socket
      |> assign(:page_title, "New Device")
      |> assign(:device, %Device{})
    else
      socket
      |> put_flash(:error, "You are not authorized to manage devices.")
      |> push_patch(to: ~p"/devices")
      |> assign(:page_title, "Listing Devices")
      |> assign(:device, nil)
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Devices")
    |> assign(:device, nil)
  end

  @impl true
  def handle_event("toggle_group_panel", _params, socket) do
    if socket.assigns.can_view_device_details? and socket.assigns.group_authorization do
      open? = not socket.assigns.group_panel_open?

      {:noreply,
       socket
       |> assign(:group_panel_open?, open?)
       |> assign(:group_form, nil)
       |> assign(:pending_group_delete, nil)
       |> maybe_queue_device_group_refresh(open?)}
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to view device groups.")}
    end
  end

  def handle_event("close_group_panel", _params, socket) do
    {:noreply,
     socket
     |> assign(:group_panel_open?, false)
     |> assign(:group_form, nil)
     |> assign(:pending_group_delete, nil)}
  end

  def handle_event("new_group", _params, socket) do
    if can_manage_group_metadata?(socket) do
      {:noreply, assign(socket, :group_form, %{id: nil, name: "", description: ""})}
    else
      {:noreply, group_metadata_denied(socket)}
    end
  end

  def handle_event("edit_group", %{"id" => group_id}, socket) do
    if can_manage_group_metadata?(socket) do
      case find_device_group(socket, group_id) do
        nil -> {:noreply, put_flash(socket, :error, "That group is no longer available.")}
        group -> {:noreply, assign(socket, :group_form, group)}
      end
    else
      {:noreply, group_metadata_denied(socket)}
    end
  end

  def handle_event("edit_group", _params, socket), do: {:noreply, group_metadata_denied(socket)}

  def handle_event("cancel_group_form", _params, socket) do
    {:noreply, assign(socket, :group_form, nil)}
  end

  def handle_event("save_group", %{"group" => attrs}, socket) when is_map(attrs) do
    if can_manage_group_metadata?(socket) do
      save_group_metadata(socket, attrs)
    else
      {:noreply, group_metadata_denied(socket)}
    end
  end

  def handle_event("save_group", _params, socket), do: {:noreply, group_metadata_denied(socket)}

  def handle_event("archive_group", %{"id" => group_id}, socket) do
    run_group_metadata_action(
      socket,
      fn authorization ->
        Devices.archive_device_group(group_id, authorization)
      end,
      "Group archived"
    )
  end

  def handle_event("archive_group", _params, socket), do: {:noreply, group_metadata_denied(socket)}

  def handle_event("restore_group", %{"id" => group_id}, socket) do
    run_group_metadata_action(
      socket,
      fn authorization ->
        Devices.restore_device_group(group_id, authorization)
      end,
      "Group restored"
    )
  end

  def handle_event("restore_group", _params, socket), do: {:noreply, group_metadata_denied(socket)}

  def handle_event("toggle_archived_groups", _params, socket) do
    if can_manage_group_metadata?(socket) do
      {:noreply,
       socket
       |> assign(:show_archived_groups?, not socket.assigns.show_archived_groups?)
       |> refresh_device_groups()}
    else
      {:noreply, group_metadata_denied(socket)}
    end
  end

  def handle_event("request_group_delete", %{"id" => group_id}, socket) do
    if can_manage_group_metadata?(socket) do
      case find_device_group(socket, group_id) do
        %{archived_at: archived_at} = group when not is_nil(archived_at) ->
          {:noreply, assign(socket, :pending_group_delete, group)}

        _group ->
          {:noreply, put_flash(socket, :error, "Only archived groups can be permanently deleted.")}
      end
    else
      {:noreply, group_metadata_denied(socket)}
    end
  end

  def handle_event("request_group_delete", _params, socket),
    do: {:noreply, group_metadata_denied(socket)}

  def handle_event("cancel_group_delete", _params, socket) do
    {:noreply, assign(socket, :pending_group_delete, nil)}
  end

  def handle_event("group_panel_keydown", %{"key" => "Escape"}, socket) do
    if socket.assigns.pending_group_delete do
      {:noreply, assign(socket, :pending_group_delete, nil)}
    else
      handle_event("close_group_panel", %{}, socket)
    end
  end

  def handle_event("group_panel_keydown", _params, socket), do: {:noreply, socket}

  def handle_event("confirm_group_delete", _params, socket) do
    case {can_manage_group_metadata?(socket), socket.assigns.pending_group_delete} do
      {true, %{id: group_id}} -> permanently_delete_group(socket, group_id)
      _state -> {:noreply, group_metadata_denied(socket)}
    end
  end

  def handle_event("select_membership_group", %{"group_id" => group_id}, socket) do
    if can_manage_group_memberships?(socket) do
      case find_active_device_group(socket, group_id) do
        nil ->
          {:noreply,
           socket
           |> assign(:selected_group_id, nil)
           |> put_flash(:error, "That group is no longer available.")}

        _group ->
          {:noreply, assign(socket, :selected_group_id, group_id)}
      end
    else
      {:noreply, group_membership_denied(socket)}
    end
  end

  def handle_event("select_membership_group", _params, socket),
    do: {:noreply, group_membership_denied(socket)}

  def handle_event("add_selected_to_group", _params, socket) do
    mutate_selected_group_memberships(socket, :add)
  end

  def handle_event("remove_selected_from_group", _params, socket) do
    mutate_selected_group_memberships(socket, :remove)
  end

  def handle_event("search", %{"search" => search}, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.put("search", search)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("filter", %{"approval_status" => status}, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.put("approval_status", status)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("filter", %{"connectivity_status" => status}, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.put("connectivity_status", status)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("add_filter", %{"key" => key, "value" => value}, socket) do
    value = normalize_blank(value)

    if is_nil(value) do
      {:noreply, put_flash(socket, :info, "No value available for this filter")}
    else
      params =
        socket.assigns
        |> get_params()
        |> Map.put(key, value)

      {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
    end
  end

  def handle_event("remove_filter", %{"key" => key}, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.delete(key)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.drop(["approval_status", "connectivity_status", "product", "account_number", "ipv4_address"])

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    sort_by_atom = Map.get(@sort_fields, sort_by, :inserted_at)

    order =
      if socket.assigns.sort_by == sort_by_atom and socket.assigns.sort_order == :asc,
        do: :desc,
        else: :asc

    params =
      socket.assigns
      |> get_params()
      |> Map.put("sort_by", sort_by)
      |> Map.put("sort_order", order)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("open_device_details", %{"id" => id}, socket) do
    if Permissions.can_view_device_details?(socket.assigns.device_permissions, id) do
      %Device{} = Devices.get_device!(id)

      :telemetry.execute(
        [:nixstasis, :devices, :details_open],
        %{count: 1},
        %{result: :ok, source: :devices_index, device_id: id}
      )

      {:noreply, push_navigate(socket, to: ~p"/devices/#{id}")}
    else
      :telemetry.execute(
        [:nixstasis, :devices, :details_open],
        %{count: 1},
        %{result: :unauthorized, source: :devices_index, device_id: id}
      )

      {:noreply, put_flash(socket, :error, "You are not authorized to view device details.")}
    end
  rescue
    _ ->
      :telemetry.execute(
        [:nixstasis, :devices, :details_open],
        %{count: 1},
        %{result: :error, source: :devices_index, device_id: id}
      )

      {:noreply, put_flash(socket, :error, "Unable to open device details")}
  end

  def handle_event("toggle_selection", %{"id" => id}, socket) do
    cond do
      not Permissions.can_manage_devices?(socket.assigns.device_permissions) ->
        {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}

      not Permissions.can_manage_device?(socket.assigns.device_permissions, id) ->
        {:noreply, put_flash(socket, :error, "You are not authorized to manage this device.")}

      true ->
        toggle_device_selection(socket, id)
    end
  end

  def handle_event("toggle_all", _params, socket) do
    if Permissions.can_manage_devices?(socket.assigns.device_permissions) do
      toggle_all_visible_devices(socket)
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}
    end
  end

  def handle_event("bulk_approve", _params, socket) do
    if Permissions.can_manage_devices?(socket.assigns.device_permissions) do
      handle_bulk_result(socket, Devices.approve_devices(socket.assigns.selected_ids), "approved", "approve")
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}
    end
  end

  def handle_event("bulk_reject", _params, socket) do
    if Permissions.can_manage_devices?(socket.assigns.device_permissions) do
      handle_bulk_result(socket, Devices.reject_devices(socket.assigns.selected_ids), "rejected", "reject")
    else
      {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}
    end
  end

  defp handle_bulk_result(socket, %{status: :success}, success_verb, _action_verb) do
    {:noreply,
     socket
     |> put_flash(:info, "Devices #{success_verb}")
     |> assign(:selected_ids, [])
     |> push_navigate(to: ~p"/devices")}
  end

  defp handle_bulk_result(socket, result, _success_verb, action_verb) do
    Logger.warning("Failed to #{action_verb} selected devices: #{inspect(result)}")

    {:noreply,
     socket
     |> put_flash(:error, "Unable to #{action_verb} selected devices.")
     |> refresh_devices()}
  end

  defp toggle_device_selection(socket, id) do
    selected = socket.assigns.selected_ids
    new_selected = if id in selected, do: List.delete(selected, id), else: [id | selected]

    {:noreply,
     socket
     |> assign(:selected_ids, new_selected)
     |> refresh_devices()}
  end

  defp toggle_all_visible_devices(socket) do
    devices = list_visible_devices(socket.assigns)
    visible_ids = Enum.map(devices, & &1.id)
    all_visible_selected? = Enum.all?(visible_ids, &(&1 in socket.assigns.selected_ids))

    new_selected =
      if all_visible_selected? do
        []
      else
        visible_ids
      end

    {:noreply,
     socket
     |> assign(:selected_ids, new_selected)
     |> refresh_devices()}
  end

  @refresh_debounce_ms 5_000

  @impl true
  def handle_info({NixstasisWeb.DeviceLive.FormComponent, {:saved, device}}, socket) do
    {:noreply, stream_insert(socket, :devices, device)}
  end

  def handle_info({:device_last_seen_updated, _device}, socket) do
    {:noreply, schedule_debounced_refresh(socket)}
  end

  def handle_info({event, _device}, socket)
      when event in [
             :device_registered,
             :device_created,
             :device_deleted,
             :device_updated,
             :device_approval_status_changed,
             :device_remote_access_changed
           ] do
    {:noreply, refresh_devices_if_authorized(socket)}
  end

  def handle_info(:load_device_groups, socket) do
    {:noreply, refresh_device_groups(socket)}
  end

  def handle_info(:device_groups_changed, socket) do
    {:noreply,
     socket
     |> refresh_devices_if_authorized()
     |> refresh_device_groups()}
  end

  def handle_info(:debounced_refresh, socket) do
    {:noreply,
     socket
     |> assign(:refresh_timer, nil)
     |> refresh_devices_if_authorized()}
  end

  def handle_info({:clear_flash, key}, socket) do
    {:noreply, clear_flash(socket, key)}
  end

  def handle_info(message, socket) do
    Logger.debug("#{__MODULE__} unhandled message: #{inspect(message)}")
    {:noreply, socket}
  end

  defp get_params(assigns) do
    %{
      "sort_by" => assigns[:sort_by],
      "sort_order" => assigns[:sort_order],
      "approval_status" => assigns[:filter_approval_status],
      "connectivity_status" => assigns[:filter_connectivity_status],
      "product" => assigns[:filter_product],
      "account_number" => assigns[:filter_account_number],
      "ipv4_address" => assigns[:filter_ipv4_address],
      "search" => assigns[:search]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp assign_unauthorized_devices_state(socket) do
    socket
    |> assign(:sort_by, :inserted_at)
    |> assign(:sort_order, :desc)
    |> assign(:filter_approval_status, nil)
    |> assign(:filter_connectivity_status, nil)
    |> assign(:filter_product, nil)
    |> assign(:filter_account_number, nil)
    |> assign(:filter_ipv4_address, nil)
    |> assign(:active_filters, %{})
    |> assign(:search, nil)
    |> assign(:current_params, %{})
    |> assign(:total_count, 0)
    |> assign(:selected_ids, [])
    |> assign(:selected_group_id, nil)
    |> assign(:device_groups, [])
    |> stream(:devices, [], reset: true)
  end

  defp can_manage_group_memberships?(socket) do
    case socket.assigns.group_authorization do
      %{can_manage_devices?: true} -> true
      _authorization -> false
    end
  end

  defp group_membership_denied(socket) do
    put_flash(socket, :error, "You are not authorized to manage group memberships.")
  end

  defp find_active_device_group(socket, group_id) do
    Enum.find_value(socket.assigns.device_groups, fn row ->
      if row.group.id == group_id and is_nil(row.group.archived_at), do: row.group
    end)
  end

  defp mutate_selected_group_memberships(socket, operation) do
    cond do
      not can_manage_group_memberships?(socket) ->
        {:noreply, group_membership_denied(socket)}

      socket.assigns.selected_ids == [] ->
        {:noreply, put_flash(socket, :error, "Select at least one device first.")}

      is_nil(socket.assigns.selected_group_id) ->
        {:noreply, put_flash(socket, :error, "That group is no longer available.")}

      true ->
        run_selected_membership_mutation(socket, operation)
    end
  end

  defp run_selected_membership_mutation(socket, operation) do
    group = find_active_device_group(socket, socket.assigns.selected_group_id)

    if group do
      result =
        case operation do
          :add ->
            Devices.add_devices_to_group(
              group.id,
              socket.assigns.selected_ids,
              socket.assigns.group_authorization
            )

          :remove ->
            Devices.remove_devices_from_group(
              group.id,
              socket.assigns.selected_ids,
              socket.assigns.group_authorization
            )
        end

      handle_selected_membership_result(socket, operation, group, result)
    else
      {:noreply,
       socket
       |> assign(:selected_group_id, nil)
       |> put_flash(:error, "That group is no longer available.")}
    end
  end

  defp handle_selected_membership_result(socket, operation, group, {:ok, result}) do
    changed_count = length(result.changed_device_ids)
    message = membership_success_message(operation, group.name, changed_count)

    {:noreply,
     socket
     |> refresh_device_groups()
     |> put_flash(:info, message)}
  end

  defp handle_selected_membership_result(socket, _operation, _group, {:error, reason}) do
    {:noreply, put_flash(socket, :error, group_membership_error(reason))}
  end

  defp membership_success_message(:add, group_name, 0),
    do: "Selected devices are already in #{group_name}."

  defp membership_success_message(:remove, group_name, 0),
    do: "Selected devices are not in #{group_name}."

  defp membership_success_message(:add, group_name, count),
    do: "Added #{count} #{device_count_label(count)} to #{group_name}."

  defp membership_success_message(:remove, group_name, count),
    do: "Removed #{count} #{device_count_label(count)} from #{group_name}."

  defp device_count_label(1), do: "device"
  defp device_count_label(_count), do: "devices"

  defp group_membership_error(:group_archived), do: "That group is archived or no longer available."
  defp group_membership_error(:group_not_found), do: "That group is archived or no longer available."
  defp group_membership_error(:group_not_visible), do: "That group is no longer available."
  defp group_membership_error(:unauthorized_devices), do: "Your device access changed. Refresh and try again."
  defp group_membership_error(:devices_not_found), do: "One or more selected devices are no longer available."
  defp group_membership_error(:unauthorized), do: "You are not authorized to manage group memberships."
  defp group_membership_error(:missing_actor), do: "Your operator identity is unavailable. Sign in again."
  defp group_membership_error(_reason), do: "Unable to update group memberships. No changes were saved."

  defp can_manage_group_metadata?(socket) do
    case socket.assigns.group_authorization do
      %{
        can_manage_devices?: true,
        can_manage_all_devices?: true,
        authorized_device_ids: nil
      } ->
        true

      _authorization ->
        false
    end
  end

  defp group_metadata_denied(socket) do
    put_flash(socket, :error, "You are not authorized to manage group metadata.")
  end

  defp maybe_queue_device_group_refresh(socket, true) do
    Process.send_after(self(), :load_device_groups, 10)

    socket
    |> assign(:groups_loading?, true)
    |> assign(:device_groups, [])
  end

  defp maybe_queue_device_group_refresh(socket, false), do: assign(socket, :groups_loading?, false)

  defp refresh_device_groups(%{assigns: %{group_authorization: nil}} = socket) do
    socket
    |> assign(:device_groups, [])
    |> assign(:selected_group_id, nil)
    |> assign(:groups_loading?, false)
  end

  defp refresh_device_groups(socket) do
    groups =
      Devices.list_device_groups(socket.assigns.group_authorization,
        include_archived?: socket.assigns.show_archived_groups?
      )

    active_group_ids =
      groups
      |> Enum.filter(&is_nil(&1.group.archived_at))
      |> Enum.map(& &1.group.id)

    selected_group_id =
      if socket.assigns.selected_group_id in active_group_ids,
        do: socket.assigns.selected_group_id,
        else: nil

    socket
    |> assign(:device_groups, groups)
    |> assign(:selected_group_id, selected_group_id)
    |> assign(:groups_loading?, false)
  end

  defp find_device_group(socket, group_id) do
    socket.assigns.device_groups
    |> Enum.find(&(&1.group.id == group_id))
    |> case do
      nil -> nil
      row -> Map.put(row.group, :visible_device_count, row.visible_device_count)
    end
  end

  defp save_group_metadata(socket, attrs) do
    name = attrs |> Map.get("name", "") |> String.trim()
    description = Map.get(attrs, "description", "")

    if name == "" do
      {:noreply,
       socket
       |> assign(:group_form, put_group_form_values(socket.assigns.group_form, name, description))
       |> put_flash(:error, "Group name is required.")}
    else
      persist_group_metadata(socket, %{name: name, description: description})
    end
  end

  defp persist_group_metadata(socket, attrs) do
    result =
      case socket.assigns.group_form do
        %{id: nil} -> Devices.create_device_group(attrs, socket.assigns.group_authorization)
        %{id: group_id} -> Devices.update_device_group(group_id, attrs, socket.assigns.group_authorization)
      end

    case result do
      {:ok, _group} ->
        message = if socket.assigns.group_form.id, do: "Group updated", else: "Group created"

        {:noreply,
         socket
         |> assign(:group_form, nil)
         |> refresh_device_groups()
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:group_form, put_group_form_values(socket.assigns.group_form, attrs.name, attrs.description))
         |> put_flash(:error, group_metadata_error(reason))}
    end
  end

  defp put_group_form_values(group_form, name, description) do
    group_form
    |> Map.put(:name, name)
    |> Map.put(:description, description)
  end

  defp run_group_metadata_action(socket, operation, success_message) do
    if can_manage_group_metadata?(socket) do
      case operation.(socket.assigns.group_authorization) do
        {:ok, _group} ->
          {:noreply,
           socket
           |> assign(:group_form, nil)
           |> refresh_device_groups()
           |> put_flash(:info, success_message)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, group_metadata_error(reason))}
      end
    else
      {:noreply, group_metadata_denied(socket)}
    end
  end

  defp permanently_delete_group(socket, group_id) do
    case Devices.permanently_delete_device_group(group_id, socket.assigns.group_authorization) do
      :ok ->
        {:noreply,
         socket
         |> assign(:pending_group_delete, nil)
         |> refresh_device_groups()
         |> put_flash(:info, "Group permanently deleted")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:pending_group_delete, nil)
         |> put_flash(:error, permanent_delete_error(reason))}
    end
  end

  defp group_metadata_error(%Ash.Changeset{errors: errors}) do
    if Enum.any?(errors, &match?(%Ash.Error.Changes.InvalidAttribute{field: :name_key}, &1)) do
      "A group with that name already exists."
    else
      "Unable to save the group. Check its name and try again."
    end
  end

  defp group_metadata_error(%Ash.Error.Invalid{} = error), do: invalid_group_metadata_error(error)
  defp group_metadata_error(%Ash.Error.Unknown{} = error), do: invalid_group_metadata_error(error)
  defp group_metadata_error(:group_not_found), do: "That group is no longer available."
  defp group_metadata_error(:group_archived), do: "That group is already archived."
  defp group_metadata_error(:group_not_archived), do: "That group is not archived."
  defp group_metadata_error(:unauthorized), do: "You are not authorized to manage group metadata."
  defp group_metadata_error(:missing_actor), do: "Your operator identity is unavailable. Sign in again."
  defp group_metadata_error(_reason), do: "Unable to change the group. Try again."

  defp invalid_group_metadata_error(error) do
    message = Exception.message(error)

    if String.contains?(message, ["name_key", "already been taken", "unique"]) do
      "A group with that name already exists."
    else
      "Unable to save the group. Check its name and try again."
    end
  end

  defp permanent_delete_error(%Ash.Changeset{}),
    do: "Remove every device before permanently deleting this group."

  defp permanent_delete_error(%Ash.Error.Unknown{}),
    do: "Remove every device before permanently deleting this group."

  defp permanent_delete_error(%Ash.Error.Invalid{}),
    do: "Remove every device before permanently deleting this group."

  defp permanent_delete_error(reason), do: group_metadata_error(reason)

  defp normalize_blank(nil), do: nil

  defp normalize_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_blank(value), do: value

  defp normalize_filter_atom(nil), do: nil
  defp normalize_filter_atom(value) when is_atom(value), do: Atom.to_string(value)

  defp refresh_devices(socket) do
    devices = list_visible_devices(socket.assigns)

    selected_ids =
      Enum.filter(socket.assigns.selected_ids, fn selected_id ->
        Enum.any?(devices, fn device -> device.id == selected_id end)
      end)

    socket
    |> assign(:selected_ids, selected_ids)
    |> assign(:total_count, length(devices))
    |> stream(:devices, devices, reset: true)
  end

  defp refresh_devices_if_authorized(socket) do
    if socket.assigns.can_view_device_details? do
      refresh_devices(socket)
    else
      assign_unauthorized_devices_state(socket)
    end
  end

  defp schedule_debounced_refresh(socket) do
    if socket.assigns.can_view_device_details? do
      schedule_authorized_debounced_refresh(socket)
    else
      socket
    end
  end

  defp schedule_authorized_debounced_refresh(socket) do
    existing = Map.get(socket.assigns, :refresh_timer)

    if existing do
      socket
    else
      timer = Process.send_after(self(), :debounced_refresh, @refresh_debounce_ms)
      assign(socket, :refresh_timer, timer)
    end
  end

  defp list_visible_devices(assigns) do
    Devices.list_devices(
      sort_by: assigns.sort_by,
      sort_order: assigns.sort_order,
      filter: %{
        approval_status: assigns.filter_approval_status,
        connectivity_status: assigns.filter_connectivity_status,
        product: assigns.filter_product,
        account_number: assigns.filter_account_number,
        ipv4_address: assigns.filter_ipv4_address
      },
      search: assigns.search
    )
    |> filter_authorized_devices(assigns.device_permissions)
  end

  defp filter_authorized_devices(devices, permissions) do
    case Permissions.authorized_device_ids(permissions) do
      nil -> devices
      ids -> Enum.filter(devices, &MapSet.member?(ids, &1.id))
    end
  end
end
