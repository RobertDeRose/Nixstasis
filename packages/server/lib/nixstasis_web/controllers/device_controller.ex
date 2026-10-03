defmodule NixstasisWeb.DeviceController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices

  action_fallback(NixstasisWeb.FallbackController)

  def index(conn, params) do
    json(conn, Devices.runtime_list(params))
  end

  def register(conn, device_params) do
    with {:ok, payload} <- Devices.register_runtime_device(device_params) do
      conn
      |> put_status(:created)
      |> json(payload)
    end
  end
end
