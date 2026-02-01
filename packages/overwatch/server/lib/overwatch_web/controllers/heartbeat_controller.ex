defmodule NixstasisWeb.HeartbeatController do
  use NixstasisWeb, :controller

  alias Nixstasis.Monitoring
  alias Nixstasis.Devices

  def create(conn, %{"device_id" => device_id} = params) do
    # T051 suggests FallbackController, but we use get_device! which raises Ecto.NoResultsError.
    # Phoenix handles 404 for that automatically.
    device = Devices.get_device!(device_id)

    if device.approval_status == "approved" do
      case Monitoring.heartbeat(device, params) do
        {:ok, _device, commands} ->
          render(conn, :show, commands: commands)
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Device not approved"})
    end
  end
end
