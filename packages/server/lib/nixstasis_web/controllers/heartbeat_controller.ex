defmodule NixstasisWeb.HeartbeatController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring

  def create(conn, %{"device_id" => device_id} = params) do
    # We use get_device! which raises when the record is missing.
    device = Devices.get_device!(device_id)

    if device.approval_status == :approved do
      case Monitoring.heartbeat(device, params) do
        {:ok, updated_device, commands} ->
          render(conn, :show, commands: commands, device: updated_device)

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Heartbeat processing failed", details: inspect(reason)})
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Device not approved"})
    end
  end
end
