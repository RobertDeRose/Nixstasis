defmodule NixstasisWeb.DeviceController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device

  action_fallback(NixstasisWeb.FallbackController)

  def index(conn, params) do
    devices =
      Devices.list_devices(
        filter: %{
          status: params["status"],
          product: params["product"],
          account_number: params["account_number"]
        }
      )

    active_filters =
      %{
        "status" => normalize_blank(params["status"]),
        "product" => normalize_blank(params["product"]),
        "account_number" => normalize_blank(params["account_number"])
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    render(conn, :index, devices: devices, meta: %{active_filters: active_filters})
  end

  def register(conn, device_params) do
    with {:ok, %Device{} = device} <- Devices.register_device(device_params) do
      conn
      |> put_status(:created)
      |> render(:show, device: device)
    end
  end

  def open_modal(conn, %{"device_id" => id}) do
    try do
      device = Devices.get_device!(id)
      {:ok, _updated} = Devices.set_remote_access(device, true)

      conn
      |> put_status(:ok)
      |> json(%{
        selected_device_id: device.id,
        remote_access_requested: true,
        pcp_data_ready: Devices.online?(device),
        terminal_ready: Devices.online?(device)
      })
    rescue
      _ -> {:error, :not_found}
    end
  end

  def close_modal(conn, %{"device_id" => id}) do
    try do
      device = Devices.get_device!(id)
      {:ok, _updated} = Devices.set_remote_access(device, false)
      send_resp(conn, :no_content, "")
    rescue
      _ -> {:error, :not_found}
    end
  end

  defp normalize_blank(nil), do: nil
  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value
end
