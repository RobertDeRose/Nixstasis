defmodule NixstasisWeb.DeviceLive.Show do
  use NixstasisWeb, :live_view

  require Logger

  import Ecto.Query

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.SshKeyManager
  alias Nixstasis.Monitoring.Telemetry
  alias Nixstasis.Repo
  alias NixstasisWeb.Permissions

  @impl true
  def mount(_params, session, socket) do
    permissions = Permissions.device_permissions(session)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Nixstasis.PubSub, "devices")
    end

    {:ok,
     socket
     |> assign(:device_permissions, permissions)
     |> assign(:can_view_device_details?, Permissions.can_view_device_details?(permissions))
     |> assign(:can_remote_access_device?, Permissions.can_remote_access_device?(permissions))
     |> assign(:remote_access_auto_open?, true)
     |> assign(:terminal_closed?, false)
     |> assign(:maximized?, false)}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    return_to = Map.get(socket.assigns, :return_to, "/devices")

    if Permissions.can_view_device_details?(socket.assigns.device_permissions, id) do
      handle_authorized_device(socket, id, return_to)
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to view device details.")
       |> push_navigate(to: return_to)}
    end
  end

  defp handle_authorized_device(socket, id, return_to) do
    case safe_get_device(id) do
      {:ok, device} ->
        view =
          if Devices.online?(device),
            do: setup_device_view(socket, device, return_to),
            else: assign_device_view(socket, device, return_to)

        {:noreply, view}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Device not found or unavailable")
         |> push_navigate(to: return_to)}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(:active_tab, tab)
      |> maybe_refresh_pcp_chart(tab)
      |> maybe_start_terminal_session(tab)

    {:noreply, socket}
  end

  @impl true
  def handle_event("retry_session", _, socket) do
    device = socket.assigns.device

    cond do
      not Permissions.can_remote_access_device?(socket.assigns.device_permissions, device.id) ->
        {:noreply, put_flash(socket, :error, "You are not authorized to reinitialize remote access for this device.")}

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
  def handle_event("toggle_maximized", _, socket) do
    {:noreply, Phoenix.Component.update(socket, :maximized?, &(!&1))}
  end

  @impl true
  def handle_event("start_ssh_session", _, socket) do
    case start_ssh_session(socket) do
      {:ok, socket} -> {:noreply, socket}
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
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
     |> assign(:ssh_authorize_command_id, nil)
     |> assign(:ssh_token, nil)
     |> assign(:terminal_socket_token, nil)
     |> assign(:terminal_closed?, false)}
  end

  @impl true
  def handle_event("terminal_authorized", %{"command_id" => command_id}, socket) do
    if command_id == socket.assigns[:ssh_authorize_command_id] do
      {:noreply, assign(socket, :ssh_authorize_command_id, nil)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("terminal_closed", %{"token" => token}, socket) do
    if token == socket.assigns[:ssh_token] do
      clear_ssh_session(socket)

      {:noreply,
       socket
       |> assign(:terminal_closed?, true)
       |> assign(:ssh_authorize_command_id, nil)
       |> assign(:terminal_socket_token, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("terminal_closed", _params, socket), do: {:noreply, socket}

  defp maybe_start_terminal_session(socket, "terminal") do
    if socket.assigns[:ssh_token] && !socket.assigns[:terminal_closed?] do
      socket
    else
      case start_ssh_session(socket) do
        {:ok, socket} -> socket
        {:error, message} -> put_flash(socket, :error, message)
      end
    end
  end

  defp maybe_start_terminal_session(socket, _tab), do: socket

  defp start_ssh_session(socket) do
    device = socket.assigns.device

    cond do
      not Permissions.can_remote_access_device?(socket.assigns.device_permissions, device.id) ->
        {:error, "You are not authorized to start remote access for this device."}

      socket.assigns.device_offline ->
        {:error, "Device is offline; unable to start remote access"}

      true ->
        clear_ssh_session(socket)

        with {:ok, %{private_key: private_key, public_key: public_key}} <-
               SshKeyManager.generate_key_pair(),
             {:ok, session_ref} <- SshKeyManager.create_terminal_session(device.id, private_key),
             {:ok, command} <-
               Devices.queue_command(
                 device,
                 build_ssh_authorize_command(device, session_ref, public_key)
               ) do
          socket_token =
            Phoenix.Token.sign(NixstasisWeb.Endpoint, "terminal_socket", %{"device_id" => device.id})

          {:ok,
           socket
           |> assign(:ssh_session_started, true)
           |> assign(:ssh_authorize_command_id, command.id)
           |> assign(:ssh_token, session_ref)
           |> assign(:terminal_socket_token, socket_token)
           |> assign(:terminal_closed?, false)}
        else
          {:error, reason} when is_binary(reason) ->
            {:error, "Failed to start SSH session: #{reason}"}

          {:error, reason} ->
            {:error, "Failed to start SSH session: #{inspect(reason)}"}
        end
    end
  end

  # Build the ssh_authorize command body. The dynamic in-memory content type
  # is the only supported shape: the client stores the key in its in-memory
  # sshauth store keyed by `session_ref` and exposes it to sshd through the
  # AuthorizedKeysCommand helper over the local IPC socket.
  defp build_ssh_authorize_command(_device, session_ref, public_key) do
    %{
      "type" => "ssh_authorize",
      "public_key" => public_key,
      "payload" => %{
        "content_type" => "application/vnd.nixstasis.ssh-authorize+json;version=1",
        "name" => session_ref,
        "data" =>
          Jason.encode!(%{
            "target_user" => "nixstasis-support",
            "ttl_seconds" => ssh_authorization_ttl_seconds(),
            "session_ref" => session_ref
          })
      }
    }
  end

  defp ssh_authorization_ttl_seconds do
    case Application.get_env(:nixstasis, :ssh_authorization_ttl_seconds) do
      seconds when is_integer(seconds) and seconds > 0 -> seconds
      _ -> 300
    end
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
       |> assign(:ssh_authorize_command_id, nil)
       |> assign(:ssh_token, nil)
       |> assign(:terminal_socket_token, nil)
       |> assign(:terminal_closed?, false)
       |> put_flash(:info, "Remote access session expired")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:device_last_seen_updated, %{id: device_id}}, %{assigns: %{device: %Device{id: device_id}}} = socket) do
    was_offline = socket.assigns.device_offline

    case safe_get_device(device_id) do
      {:ok, device} ->
        now_offline = not Devices.online?(device)

        socket =
          if was_offline != now_offline do
            refresh_device_view(socket, device)
          else
            assign_device_view(socket, device, socket.assigns.return_to)
          end

        {:noreply, maybe_refresh_pcp_chart(socket, socket.assigns[:active_tab])}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_info({:device_last_seen_updated, _payload}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({event, %{id: device_id}}, %{assigns: %{device: %Device{id: device_id}}} = socket)
      when event in [
             :device_created,
             :device_registered,
             :device_updated,
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
             :device_approval_status_changed,
             :device_remote_access_changed
           ] do
    {:noreply, socket}
  end

  def handle_info(message, socket) do
    Logger.debug("#{__MODULE__} unhandled message: #{inspect(message)}")
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

    latest_pcp = latest_pcp_sample(device.id)

    socket
    |> assign(:remote_access_auto_open?, true)
    |> assign_device_view(device, return_to)
    |> assign(:remote_access_lease_ref, lease_ref)
    |> assign(:active_tab, "pcp")
    |> assign(:ssh_session_started, false)
    |> assign(:ssh_authorize_command_id, nil)
    |> assign(:ssh_token, nil)
    |> assign(:terminal_socket_token, nil)
    |> assign(:terminal_closed?, false)
    |> assign(:cpu_chart, chart_config("CPU Load", [latest_pcp.load_1m], ["#3B82F6"]))
    |> assign(:memory_chart, chart_config("Memory Used %", [latest_pcp.memory_used_pct], ["#10B981"]))
    |> assign(:disk_chart, chart_config("Disk Full %", [latest_pcp.disk_full_pct], ["#F59E0B"]))
    |> assign(:pcp_chart, pcp_chart_config(device))
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

  defp maybe_refresh_pcp_chart(%{assigns: %{device: %Device{} = device}} = socket, "pcp") do
    assign(socket, :pcp_chart, pcp_chart_config(device))
  end

  defp maybe_refresh_pcp_chart(socket, _tab), do: socket

  defp maybe_clear_ssh_assigns(socket, device) do
    if Devices.online?(device) do
      socket
    else
      socket
      |> assign(:ssh_session_started, false)
      |> assign(:ssh_authorize_command_id, nil)
      |> assign(:ssh_token, nil)
      |> assign(:terminal_socket_token, nil)
      |> assign(:terminal_closed?, false)
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
      latest_pcp = latest_pcp_sample(device.id)

      socket
      |> assign_new(:active_tab, fn -> "pcp" end)
      |> assign(:cpu_chart, chart_config("CPU Load", [latest_pcp.load_1m], ["#3B82F6"]))
      |> assign(:memory_chart, chart_config("Memory Used %", [latest_pcp.memory_used_pct], ["#10B981"]))
      |> assign(:disk_chart, chart_config("Disk Full %", [latest_pcp.disk_full_pct], ["#F59E0B"]))
      |> assign(:pcp_chart, pcp_chart_config(device))
      |> assign_new(:ssh_session_started, fn -> false end)
      |> assign_new(:ssh_authorize_command_id, fn -> nil end)
      |> assign_new(:ssh_token, fn -> nil end)
      |> assign_new(:terminal_socket_token, fn -> nil end)
      |> assign_new(:terminal_closed?, fn -> false end)
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
    case Map.get(socket.assigns, :ssh_token) do
      nil ->
        :ok

      session_ref ->
        _ = Devices.queue_terminal_revoke(socket.assigns.device, session_ref)
        SshKeyManager.clear_terminal_session(session_ref)
    end
  end

  defp close_remote_access(socket) do
    socket.assigns
    |> Map.get(:remote_access_lease_ref)
    |> Devices.close_remote_access_lease()
  end

  defp pcp_chart_config(device) do
    samples = pcp_samples(device.id)

    %{
      chart: %{
        type: "area",
        height: 600,
        animations: %{
          enabled: false
        },
        zoom: %{enabled: false}
      },
      dataLabels: %{enabled: false},
      stroke: %{curve: "smooth", width: 3},
      fill: %{type: "gradient", gradient: %{opacityFrom: 0.22, opacityTo: 0.02}},
      markers: %{size: 0, hover: %{size: 5}},
      tooltip: %{shared: true, intersect: false},
      legend: %{
        position: "top",
        horizontalAlign: "left",
        offsetX: 0,
        offsetY: 0,
        markers: %{width: 12, height: 12, radius: 2}
      },
      title: %{text: "PCP Metrics", align: "left"},
      noData: %{text: "Waiting for PCP telemetry..."},
      series: [
        %{name: "Load 1m", data: Enum.map(samples, & &1.load_1m)},
        %{name: "Memory Used %", data: Enum.map(samples, & &1.memory_used_pct)},
        %{name: "Disk Full %", data: Enum.map(samples, & &1.disk_full_pct)}
      ],
      xaxis: %{
        categories: Enum.map(samples, & &1.label),
        labels: %{
          rotate: -45,
          rotateAlways: true,
          hideOverlappingLabels: true,
          trim: false,
          style: %{fontSize: "11px"}
        },
        tickAmount: 8,
        axisTicks: %{offsetY: -4}
      }
    }
  end

  defp pcp_samples(device_id) do
    Telemetry
    |> where([event], event.device_id == ^device_id)
    |> order_by([event], desc: event.timestamp)
    |> limit(24)
    |> Repo.all()
    |> Enum.reverse()
    |> Enum.flat_map(&pcp_sample/1)
  end

  defp latest_pcp_sample(device_id) do
    device_id
    |> pcp_samples()
    |> List.last(%{load_1m: 0, memory_used: 0, memory_used_pct: 0, disk_full_pct: 0})
  end

  defp pcp_sample(%Telemetry{timestamp: timestamp, payload: payload}) do
    with %{} = pcp <- pcp_payload(payload),
         {:ok, load_1m} <- number_value(pcp["load_1m"]),
         {:ok, memory_used} <- number_value(pcp["memory_used"]),
         {:ok, memory_used_pct} <- number_value(pcp["memory_used_pct"]),
         {:ok, disk_full_pct} <- number_value(pcp["disk_full_pct"]) do
      [
        %{
          label: Calendar.strftime(timestamp, "%H:%M:%S"),
          load_1m: round_float(load_1m),
          memory_used: round_float(memory_used),
          memory_used_pct: round_float(memory_used_pct),
          disk_full_pct: round_float(disk_full_pct)
        }
      ]
    else
      _ -> []
    end
  end

  defp pcp_payload(payload) do
    get_in(payload, ["scripts", "pcp", "data", "output"]) ||
      get_in(payload, ["scripts", "pcp", "data"])
  end

  defp number_value(value) when is_integer(value), do: {:ok, value}
  defp number_value(value) when is_float(value), do: {:ok, value}

  defp number_value(value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  defp number_value(_value), do: :error

  defp round_float(value) when is_integer(value), do: value
  defp round_float(value) when is_float(value), do: Float.round(value, 2)

  defp chart_config(label, data, colors) do
    %{
      chart: %{
        type: "radialBar",
        height: 250,
        animations: %{
          enabled: false
        },
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
              fontSize: "13px",
              fontWeight: 600
            },
            value: %{
              offsetY: 5,
              fontSize: "20px",
              fontWeight: 700,
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
