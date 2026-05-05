defmodule NixstasisWeb.DeviceLive.Show do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.SshKeyManager

  @impl true
  def mount(_params, session, socket) do
    permissions = device_permissions(session)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")
    end

    {:ok,
     socket
      |> assign(:device_permissions, permissions)
      |> assign(:can_view_device_details?, can_view_device_details?(permissions))
      |> assign(:can_remote_access_device?, can_remote_access_device?(permissions))
      |> assign(:remote_access_auto_open?, true)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    return_to = Map.get(socket.assigns, :return_to, "/devices")

    cond do
      not can_view_device_details?(socket.assigns.device_permissions, id) ->
        {:noreply,
         socket
          |> put_flash(:error, "You are not authorized to view device details.")
         |> push_navigate(to: return_to)}

      true ->
        case safe_get_device(id) do
          {:ok, device} ->
            if Devices.online?(device) do
              {:noreply, setup_device_view(socket, device, return_to)}
            else
              {:noreply, assign_device_view(socket, device, return_to)}
            end

          :error ->
            {:noreply,
             socket
             |> put_flash(:error, "Device not found or unavailable")
             |> push_navigate(to: return_to)}
        end
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("retry_session", _, socket) do
    device = socket.assigns.device

    cond do
      not can_remote_access_device?(socket.assigns.device_permissions, device.id) ->
        {:noreply,
         put_flash(socket, :error, "You are not authorized to reinitialize remote access for this device.")}

      Devices.online?(device) ->
        {:noreply,
         socket
         |> setup_device_view(device, socket.assigns.return_to)
         |> put_flash(:info, "Session reinitialized")}

      true ->
        {:noreply, put_flash(socket, :error, "Device is offline; unable to reinitialize session")}
    end
  end

  @impl true
  def handle_event("start_ssh_session", _, socket) do
    device = socket.assigns.device

    cond do
      not can_remote_access_device?(socket.assigns.device_permissions, device.id) ->
        {:noreply,
         put_flash(socket, :error, "You are not authorized to start remote access for this device.")}

      socket.assigns.device_offline ->
        {:noreply, put_flash(socket, :error, "Device is offline; unable to start remote access")}

      true ->
        case SshKeyManager.generate_key_pair() do
          {:ok, %{private_key: private_key, public_key: public_key}} ->
            {:ok, _} =
              Devices.queue_command(device, %{"type" => "ssh_authorize", "public_key" => public_key})

            {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, private_key)

            socket_token =
              Phoenix.Token.sign(NixstasisWeb.Endpoint, "terminal_socket", %{"device_id" => device.id})

            {:noreply,
             socket
             |> assign(:ssh_session_started, true)
             |> assign(:ssh_token, session_ref)
             |> assign(:terminal_socket_token, socket_token)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to generate SSH keys: #{reason}")}
        end
    end
  end

  @impl true
  def handle_event("close_remote_access", _, socket) do
    close_session(socket)

    {:noreply,
      socket
      |> assign(:remote_access_auto_open?, false)
      |> assign(:remote_access_lease_ref, nil)
      |> assign(:ssh_session_started, false)
      |> assign(:ssh_token, nil)
      |> assign(:terminal_socket_token, nil)}
  end

  @impl true
  def handle_info({:remote_access_lease_expired, lease_ref}, socket) do
    if socket.assigns[:remote_access_lease_ref] == lease_ref do
      clear_ssh_session(socket)
      Devices.expire_remote_access_lease(lease_ref)

      {:noreply,
        socket
        |> assign(:remote_access_auto_open?, false)
        |> assign(:remote_access_lease_ref, nil)
        |> assign(:ssh_session_started, false)
        |> assign(:ssh_token, nil)
        |> assign(:terminal_socket_token, nil)
        |> put_flash(:info, "Remote access session expired")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({event, %{id: device_id}}, %{assigns: %{device: %Device{id: device_id}}} = socket)
      when event in [
            :device_created,
            :device_registered,
            :device_updated,
            :device_last_seen_updated,
            :device_approval_status_changed,
            :device_remote_access_changed
           ] do
    case safe_get_device(device_id) do
      {:ok, device} ->
        {:noreply, refresh_device_view(socket, device)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Device not found or unavailable")
         |> push_navigate(to: socket.assigns.return_to || "/devices")}
    end
  end

  def handle_info({event, _payload}, socket)
      when event in [
            :device_created,
            :device_registered,
            :device_updated,
            :device_last_seen_updated,
            :device_approval_status_changed,
            :device_remote_access_changed
           ] do
    {:noreply, socket}
  end

  defp safe_get_device(id) do
    {:ok, Devices.get_device!(id)}
  rescue
    _ -> :error
  end

  defp setup_device_view(socket, device, return_to) do
    close_session(socket)

    {device, lease_ref} =
      if connected?(socket) and socket.assigns.can_remote_access_device? do
        {:ok, device, lease_ref} = Devices.open_remote_access_lease(device, owner: self())
        {device, lease_ref}
      else
        {device, nil}
      end

    socket
    |> assign(:remote_access_auto_open?, true)
    |> assign_device_view(device, return_to)
    |> assign(:remote_access_lease_ref, lease_ref)
    |> assign(:active_tab, "overview")
    |> assign(:ssh_session_started, false)
    |> assign(:ssh_token, nil)
    |> assign(:terminal_socket_token, nil)
    |> assign(:cpu_chart, chart_config("CPU Usage", [75], ["#3B82F6"]))
    |> assign(:memory_chart, chart_config("Memory Usage", [45], ["#10B981"]))
    |> assign(:disk_chart, chart_config("Disk Usage", [60], ["#F59E0B"]))
    |> assign(:pcp_chart, line_chart_config())
  end

  defp refresh_device_view(socket, device) do
    socket
    |> maybe_close_remote_access_lease(device)
    |> maybe_open_remote_access_lease(device)
    |> assign_device_view(device, socket.assigns.return_to)
    |> ensure_online_view_assigns(device)
    |> maybe_clear_ssh_assigns(device)
  end

  defp maybe_close_remote_access_lease(socket, device) do
    if Devices.online?(device) or is_nil(socket.assigns[:remote_access_lease_ref]) do
      socket
    else
      Devices.close_remote_access_lease(socket.assigns.remote_access_lease_ref)

      socket
      |> assign(:remote_access_lease_ref, nil)
    end
  end

  defp assign_device_view(socket, device, return_to) do
    socket
    |> assign(:return_to, return_to)
    |> assign(:page_title, page_title(device))
    |> assign(:device, device)
    |> assign(:cockpit_url, cockpit_url(device.mac_address))
    |> assign(:device_offline, not Devices.online?(device))
  end

  defp maybe_clear_ssh_assigns(socket, device) do
    if Devices.online?(device) do
      socket
    else
      socket
      |> assign(:ssh_session_started, false)
      |> assign(:ssh_token, nil)
      |> assign(:terminal_socket_token, nil)
    end
  end

  defp maybe_open_remote_access_lease(socket, device) do
    if connected?(socket) and Devices.online?(device) and socket.assigns.can_remote_access_device? and
         Map.get(socket.assigns, :remote_access_auto_open?, true) and
         is_nil(socket.assigns[:remote_access_lease_ref]) do
      {:ok, device, lease_ref} = Devices.open_remote_access_lease(device, owner: self())

      socket
      |> assign(:device, device)
      |> assign(:remote_access_lease_ref, lease_ref)
    else
      socket
    end
  end

  defp ensure_online_view_assigns(socket, device) do
    if Devices.online?(device) do
      socket
      |> assign_new(:active_tab, fn -> "overview" end)
      |> assign_new(:cpu_chart, fn -> chart_config("CPU Usage", [75], ["#3B82F6"]) end)
      |> assign_new(:memory_chart, fn -> chart_config("Memory Usage", [45], ["#10B981"]) end)
      |> assign_new(:disk_chart, fn -> chart_config("Disk Usage", [60], ["#F59E0B"]) end)
      |> assign_new(:pcp_chart, fn -> line_chart_config() end)
      |> assign_new(:ssh_session_started, fn -> false end)
      |> assign_new(:ssh_token, fn -> nil end)
      |> assign_new(:terminal_socket_token, fn -> nil end)
    else
      socket
    end
  end

  defp page_title(device) do
    if Devices.online?(device) do
      "Device #{device.mac_address}"
    else
      "Device #{device.mac_address} - Offline"
    end
  end

  defp cockpit_url(mac_address) do
    normalized_mac =
      mac_address
      |> to_string()
      |> String.downcase()
      |> String.replace(":", "")

    domain_suffix =
      Application.get_env(
        :nixstasis,
        :cockpit_domain_suffix,
        Application.get_env(:nixstasis, :base_domain, "example.com")
      )

    domain_prefix = Application.get_env(:nixstasis, :cockpit_domain_prefix, "atom-")

    "https://#{domain_prefix}#{normalized_mac}.#{domain_suffix}"
  end

  @impl true
  def terminate(_reason, socket) do
    close_session(socket)

    :ok
  end

  defp close_session(socket) do
    clear_ssh_session(socket)
    close_remote_access(socket)
  end

  defp clear_ssh_session(socket) do
    socket.assigns
    |> Map.get(:ssh_token)
    |> SshKeyManager.clear_terminal_session()
  end

  defp close_remote_access(socket) do
    socket.assigns
    |> Map.get(:remote_access_lease_ref)
    |> Devices.close_remote_access_lease()
  end

  defp can_view_device_details?(permissions, device_id \\ nil)

  defp can_view_device_details?(permissions, nil) when is_map(permissions) do
    permissions["can_view"] == true
  end

  defp can_view_device_details?(permissions, device_id) when is_map(permissions) do
    permissions["can_view"] == true and device_authorized?(permissions, device_id)
  end

  defp can_view_device_details?(_, _), do: false

  defp can_remote_access_device?(permissions, device_id \\ nil)

  defp can_remote_access_device?(permissions, nil) when is_map(permissions) do
    permissions["can_remote_access"] == true
  end

  defp can_remote_access_device?(permissions, device_id) when is_map(permissions) do
    permissions["can_remote_access"] == true and device_authorized?(permissions, device_id)
  end

  defp can_remote_access_device?(_, _), do: false

  defp device_permissions(session) when is_map(session) do
    case Map.get(session, "device_permissions") do
      permissions when is_map(permissions) -> permissions
      _ -> %{}
    end
  end

  defp device_permissions(_session), do: %{}

  defp device_authorized?(permissions, device_id) when is_binary(device_id) do
    case authorized_device_ids(permissions) do
      nil -> true
      ids -> MapSet.member?(ids, device_id)
    end
  end

  defp device_authorized?(_permissions, _device_id), do: false

  defp authorized_device_ids(permissions) when is_map(permissions) do
    ids =
      [
        Map.get(permissions, "device_id"),
        Map.get(permissions, "device_ids"),
        Map.get(permissions, "allowed_device_ids")
      ]
      |> Enum.flat_map(&normalize_authorized_device_ids/1)
      |> Enum.uniq()

    cond do
      ids != [] -> MapSet.new(ids)
      scoped_device_permissions?(permissions) -> MapSet.new()
      true -> nil
    end
  end

  defp authorized_device_ids(_permissions), do: nil

  defp scoped_device_permissions?(permissions) when is_map(permissions) do
    Enum.any?(["device_id", "device_ids", "allowed_device_ids"], &Map.has_key?(permissions, &1))
  end

  defp scoped_device_permissions?(_permissions), do: false

  defp normalize_authorized_device_ids(value) when is_binary(value), do: [value]
  defp normalize_authorized_device_ids(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_authorized_device_ids(_value), do: []

  defp line_chart_config do
    %{
      chart: %{
        type: "line",
        height: 350,
        zoom: %{enabled: false}
      },
      dataLabels: %{enabled: false},
      stroke: %{curve: "straight"},
      title: %{text: "System Metrics (Last 24h)", align: "left"},
      series: [
        %{
          name: "CPU Load",
          data: [10, 41, 35, 51, 49, 62, 69, 91, 148]
        },
        %{
          name: "Memory Usage",
          data: [20, 31, 25, 41, 39, 52, 59, 81, 138]
        }
      ],
      xaxis: %{
        categories: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep"]
      }
    }
  end

  defp chart_config(label, data, colors) do
    %{
      chart: %{
        type: "radialBar",
        height: 250,
        sparkline: %{
          enabled: true
        }
      },
      series: data,
      colors: colors,
      labels: [label],
      plotOptions: %{
        radialBar: %{
          hollow: %{size: "70%"},
          track: %{
            background: "#e7e7e7",
            strokeWidth: "97%",
            margin: 5,
            dropShadow: %{
              enabled: true,
              top: 2,
              left: 0,
              color: "#999",
              opacity: 1,
              blur: 2
            }
          },
          dataLabels: %{
            show: true,
            name: %{
              show: true,
              offsetY: -10,
              color: "#888",
              fontSize: "13px"
            },
            value: %{
              offsetY: 5,
              color: "#111",
              fontSize: "20px",
              show: true
            }
          }
        }
      },
      fill: %{
        type: "gradient",
        gradient: %{
          shade: "light",
          shadeIntensity: 0.4,
          inverseColors: false,
          opacityFrom: 1,
          opacityTo: 1,
          stops: [0, 50, 53, 91]
        }
      }
    }
  end
end
