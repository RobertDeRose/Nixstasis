defmodule NixstasisWeb.DeviceController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device

  action_fallback(NixstasisWeb.FallbackController)

  def index(conn, params) do
    devices =
      Devices.list_devices(
        filter: %{
          approval_status: params["approval_status"],
          connectivity_status: params["connectivity_status"],
          product: params["product"],
          account_number: params["account_number"],
          ipv4_address: params["ipv4_address"]
        }
      )

    active_filters =
      %{
        "approval_status" =>
          params["approval_status"]
          |> Devices.normalize_approval_status_filter()
          |> normalize_filter_atom(),
        "connectivity_status" =>
          params["connectivity_status"]
          |> Devices.normalize_connectivity_status_filter()
          |> normalize_filter_atom(),
        "product" => normalize_blank(params["product"]),
        "account_number" => normalize_blank(params["account_number"]),
        "ipv4_address" => normalize_blank(params["ipv4_address"])
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    render(conn, :index, devices: devices, meta: %{active_filters: active_filters})
  end

  def register(conn, device_params) do
    with {:ok, %Device{} = device} <- Devices.register_public_device(device_params) do
      {device, token} = maybe_issue_approved_token(device)

      conn
      |> put_status(:created)
      |> json(%{data: device_data(device, token)})
    end
  end

  defp normalize_blank(nil), do: nil
  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value

  defp maybe_issue_approved_token(%Device{approval_status: :approved} = device) do
    case Devices.issue_device_token(device) do
      {:ok, updated_device, token} -> {updated_device, token}
      {:error, _reason} -> {device, nil}
    end
  end

  defp maybe_issue_approved_token(%Device{} = device), do: {device, nil}

  defp device_data(%Device{} = device, token) do
    data = %{
      id: device.id,
      mac_address: device.mac_address,
      product_name: device.product_name,
      account_number: device.account_number,
      approval_status: device.approval_status,
      last_seen_at: device.last_seen_at,
      schema: device.schema,
      metadata: device.metadata,
      remote_access_requested: device.remote_access_requested
    }

    if is_binary(token), do: Map.put(data, :api_token, token), else: data
  end

  defp normalize_filter_atom(nil), do: nil
  defp normalize_filter_atom(value) when is_atom(value), do: Atom.to_string(value)
end
