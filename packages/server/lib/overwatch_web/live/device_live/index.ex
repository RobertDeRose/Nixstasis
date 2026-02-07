defmodule NixstasisWeb.DeviceLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream(:devices, [])
     |> assign(:selected_ids, [])
     # Placeholder for pagination if needed
     |> assign(:meta, %{page: 1, per_page: 50})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    sort_by = safe_to_existing_atom(params["sort_by"] || "inserted_at", :inserted_at)
    sort_order = safe_to_existing_atom(params["sort_order"] || "desc", :desc)
    filter_status = if params["status"] == "", do: nil, else: params["status"] || :approved
    search = params["search"]

    opts = [
      sort_by: sort_by,
      sort_order: sort_order,
      filter: %{status: filter_status},
      search: search
    ]

    devices = Devices.list_devices(opts)

    socket =
      socket
      |> assign(:sort_by, sort_by)
      |> assign(:sort_order, sort_order)
      |> assign(:filter_status, filter_status)
      |> assign(:search, search)
      |> assign(:total_count, length(devices))
      |> stream(:devices, devices, reset: true)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Device")
    |> assign(:device, %Device{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Devices")
    |> assign(:device, nil)
  end

  defp safe_to_existing_atom(value, default) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> default
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.put("search", search)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("filter", %{"status" => status}, socket) do
    params =
      socket.assigns
      |> get_params()
      |> Map.put("status", status)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("sort", %{"sort_by" => sort_by}, socket) do
    order =
      if socket.assigns.sort_by == String.to_atom(sort_by) and socket.assigns.sort_order == :asc,
        do: :desc,
        else: :asc

    params =
      socket.assigns
      |> get_params()
      |> Map.put("sort_by", sort_by)
      |> Map.put("sort_order", order)

    {:noreply, push_patch(socket, to: ~p"/devices?#{params}")}
  end

  def handle_event("toggle_selection", %{"id" => id}, socket) do
    selected = socket.assigns.selected_ids
    new_selected = if id in selected, do: List.delete(selected, id), else: [id | selected]
    {:noreply, assign(socket, :selected_ids, new_selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    opts = [
      filter: %{status: socket.assigns.filter_status},
      search: socket.assigns.search
    ]

    devices = Devices.list_devices(opts)
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
     |> stream(:devices, devices, reset: true)}
  end

  def handle_event("bulk_approve", _params, socket) do
    Devices.approve_devices(socket.assigns.selected_ids)

    {:noreply,
     socket
     |> put_flash(:info, "Devices approved")
     |> assign(:selected_ids, [])
     # Refresh
     |> push_navigate(to: ~p"/devices")}
  end

  def handle_event("bulk_reject", _params, socket) do
    Devices.reject_devices(socket.assigns.selected_ids)

    {:noreply,
     socket
     |> put_flash(:info, "Devices rejected")
     |> assign(:selected_ids, [])
     # Refresh
     |> push_navigate(to: ~p"/devices")}
  end

  @impl true
  def handle_info({NixstasisWeb.DeviceLive.FormComponent, {:saved, device}}, socket) do
    {:noreply, stream_insert(socket, :devices, device)}
  end

  defp get_params(assigns) do
    %{
      "sort_by" => assigns[:sort_by],
      "sort_order" => assigns[:sort_order],
      "status" => assigns[:filter_status],
      "search" => assigns[:search]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end
end
