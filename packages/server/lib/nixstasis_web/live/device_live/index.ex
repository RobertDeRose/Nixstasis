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

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")
    end

    {:ok,
     socket
     |> stream(:devices, [])
     |> assign(:selected_ids, [])
     |> assign(:active_filters, %{})
     |> assign(:device_permissions, permissions)
     |> assign(:can_view_device_details?, Permissions.can_view_device_details?(permissions))
     # Placeholder for pagination if needed
     |> assign(:meta, %{page: 1, per_page: 50})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    if not socket.assigns.can_view_device_details? do
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to view devices.")
       |> assign_unauthorized_devices_state()
       |> apply_action(socket.assigns.live_action, params)}
    else
      handle_authorized_params(params, socket)
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
    cond do
      not Permissions.can_view_device_details?(socket.assigns.device_permissions, id) ->
        :telemetry.execute(
          [:nixstasis, :devices, :details_open],
          %{count: 1},
          %{result: :unauthorized, source: :devices_index, device_id: id}
        )

        {:noreply, put_flash(socket, :error, "You are not authorized to view device details.")}

      true ->
        case Devices.get_device!(id) do
          %Device{} ->
            :telemetry.execute(
              [:nixstasis, :devices, :details_open],
              %{count: 1},
              %{result: :ok, source: :devices_index, device_id: id}
            )

            {:noreply, push_navigate(socket, to: ~p"/devices/#{id}")}
        end
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
    if not Permissions.can_manage_devices?(socket.assigns.device_permissions) do
      {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}
    else
      toggle_all_visible_devices(socket)
    end
  end

  def handle_event("bulk_approve", _params, socket) do
    if not Permissions.can_manage_devices?(socket.assigns.device_permissions) do
      {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}
    else
      handle_bulk_result(socket, Devices.approve_devices(socket.assigns.selected_ids), "approved", "approve")
    end
  end

  def handle_event("bulk_reject", _params, socket) do
    if not Permissions.can_manage_devices?(socket.assigns.device_permissions) do
      {:noreply, put_flash(socket, :error, "You are not authorized to manage devices.")}
    else
      handle_bulk_result(socket, Devices.reject_devices(socket.assigns.selected_ids), "rejected", "reject")
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
    |> stream(:devices, [], reset: true)
  end

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
    if not socket.assigns.can_view_device_details? do
      socket
    else
      schedule_authorized_debounced_refresh(socket)
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
