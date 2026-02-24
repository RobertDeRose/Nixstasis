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

        # Generate a token with the private key for the terminal channel
        token = Phoenix.Token.sign(NixstasisWeb.Endpoint, "ssh_private_key", private_key)

        {:noreply,
         socket
         |> assign(:ssh_session_started, true)
         |> assign(:ssh_token, token)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to generate SSH keys: #{reason}")}
    end
  end

  defp safe_get_device(id) do
    {:ok, Devices.get_device!(id)}
  rescue
    _ -> :error
  end

  defp setup_device_view(socket, device, return_to) do
    if !device.remote_access_requested do
      Devices.set_remote_access(device, true)
    end

    socket
    |> assign(:return_to, return_to)
    |> assign(:page_title, "Device #{device.mac_address}")
    |> assign(:device, device)
    |> assign(:cockpit_url, cockpit_url(device.mac_address))
    |> assign(:device_offline, false)
    |> assign(:active_tab, "overview")
    |> assign(:ssh_session_started, false)
    |> assign(:ssh_token, nil)
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

    domain_suffix = Application.get_env(:nixstasis, :cockpit_domain_suffix, "device.<domain>")
    domain_prefix = Application.get_env(:nixstasis, :cockpit_domain_prefix, "atom-")

    "https://#{domain_prefix}#{normalized_mac}.#{domain_suffix}"
  end

  @impl true
  def terminate(_reason, socket) do
    # Task 4.2: Set remote_access_requested: false on terminate
    if socket.assigns[:device] do
      try do
        Devices.set_remote_access(socket.assigns.device, false)
      rescue
        _ -> :ok
      end
    end

    :ok
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
