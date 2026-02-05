defmodule NixstasisWeb.DeviceLive.Index do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  # alias Nixstasis.Devices.Device

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

    filter_status =
      cond do
        params["status"] not in [nil, ""] -> params["status"]
        socket.assigns.live_action == :approvals -> "pending"
        true -> nil
      end

    search = params["search"]

    opts = [
      sort_by: sort_by,
      sort_order: sort_order,
      filter: %{status: filter_status},
      search: search
    ]

    devices = Devices.list_devices(opts)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sort_order, sort_order)
     |> assign(:filter_status, filter_status)
     |> assign(:search, search)
     |> stream(:devices, devices, reset: true)}
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
    # For streams, "all" is tricky without keeping list in memory.
    # Assuming we select currently visible or fetch IDs.
    # For simplicity, if empty select all loaded, if not empty deselect all.
    current_ids =
      socket.assigns.streams.devices.inserts |> Enum.map(fn {_id, item} -> item.id end)

    new_selected =
      if Enum.empty?(socket.assigns.selected_ids) do
        current_ids
      else
        []
      end

    {:noreply, assign(socket, :selected_ids, new_selected)}
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

  def online?(device) do
    case device.last_seen_at do
      nil -> false
      time -> DateTime.diff(DateTime.utc_now(), time, :minute) < 5
    end
  end
end
