defmodule NixstasisWeb.DeviceLive.Show do
  use NixstasisWeb, :live_view

  alias Nixstasis.Devices
  alias Nixstasis.Devices.SshKeyManager

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    return_to = Map.get(socket.assigns, :return_to, "/devices")

    case safe_get_device(id) do
      {:ok, device} ->
        if Devices.online?(device) do
          {:noreply, setup_device_view(socket, device, return_to)}
        else
          {:noreply,
           socket
           |> assign(:return_to, return_to)
           |> assign(:page_title, "Device #{device.mac_address} - Offline")
           |> assign(:device, device)
           |> assign(:device_offline, true)}
        end

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Device not found or unavailable")
         |> push_navigate(to: return_to)}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("retry_session", _, socket) do
    device = socket.assigns.device

    if Devices.online?(device) do
      {:noreply,
       socket
       |> setup_device_view(device, socket.assigns.return_to)
       |> put_flash(:info, "Session reinitialized")}
    else
      {:noreply, put_flash(socket, :error, "Device is offline; unable to reinitialize session")}
    end
  end

  @impl true
  def handle_event("start_ssh_session", _, socket) do
    device = socket.assigns.device

    case SshKeyManager.generate_key_pair() do
      {:ok, %{private_key: private_key, public_key: public_key}} ->
        # Queue the command for the device
        {:ok, _} =
          Devices.queue_command(device, %{"type" => "ssh_authorize", "public_key" => public_key})

        {:ok, session_ref} = SshKeyManager.create_terminal_session(device.id, private_key)
        socket_token = Phoenix.Token.sign(NixstasisWeb.Endpoint, "terminal_socket", %{"device_id" => device.id})

        {:noreply,
         socket
         |> assign(:ssh_session_started, true)
         |> assign(:ssh_token, session_ref)
         |> assign(:terminal_socket_token, socket_token)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate SSH keys: #{reason}")}
    end
  end

  @impl true
  def handle_event("close_remote_access", _, socket) do
    close_session(socket)

    {:noreply,
     socket
     |> assign(:remote_access_lease_ref, nil)
     |> assign(:ssh_session_started, false)
     |> assign(:ssh_token, nil)}
  end

  @impl true
  def handle_info({:remote_access_lease_expired, lease_ref}, socket) do
    if socket.assigns[:remote_access_lease_ref] == lease_ref do
      clear_ssh_session(socket)
      Devices.expire_remote_access_lease(lease_ref)

      {:noreply,
       socket
       |> assign(:remote_access_lease_ref, nil)
       |> assign(:ssh_session_started, false)
       |> assign(:ssh_token, nil)
       |> put_flash(:info, "Remote access session expired")}
    else
      {:noreply, socket}
    end
  end

  defp safe_get_device(id) do
    {:ok, Devices.get_device!(id)}
  rescue
    _ -> :error
  end

  defp setup_device_view(socket, device, return_to) do
    close_session(socket)

    {device, lease_ref} =
      if connected?(socket) do
        {:ok, device, lease_ref} = Devices.open_remote_access_lease(device, owner: self())
        {device, lease_ref}
      else
        {device, nil}
      end

    socket
    |> assign(:return_to, return_to)
    |> assign(:page_title, "Device #{device.mac_address}")
    |> assign(:device, device)
    |> assign(:remote_access_lease_ref, lease_ref)
    |> assign(:cockpit_url, cockpit_url(device.mac_address))
    |> assign(:device_offline, false)
    |> assign(:active_tab, "overview")
    |> assign(:ssh_session_started, false)
    |> assign(:ssh_token, nil)
    |> assign(:terminal_socket_token, nil)
    |> assign(:cpu_chart, chart_config("CPU Usage", [75], ["#3B82F6"]))
    |> assign(:memory_chart, chart_config("Memory Usage", [45], ["#10B981"]))
    |> assign(:disk_chart, chart_config("Disk Usage", [60], ["#F59E0B"]))
    |> assign(:pcp_chart, line_chart_config())
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
