defmodule NixstasisWeb.DeviceController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device

  action_fallback(NixstasisWeb.FallbackController)

  def register(conn, device_params) do
    with {:ok, %Device{} = device} <- Devices.register_device(device_params) do
      conn
      |> put_status(:created)
      |> render(:show, device: device)
    end
  end
end
