defmodule NixstasisWeb.HeartbeatController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring

  def create(conn, %{"device_id" => device_id} = params) do
    with {:ok, device} <- fetch_device(device_id),
         :ok <- authenticate(conn, device) do
      case Monitoring.heartbeat(device, params) do
        {:ok, updated_device, commands} ->
          render(conn, :show, commands: commands, device: updated_device)

        {:error, _reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: %{code: "heartbeat_failed", message: "Heartbeat processing failed"}})
      end
    else
      {:error, :not_found} -> error(conn, :not_found, "device_not_found", "Device not found")
      {:error, :missing_token} -> error(conn, :unauthorized, "missing_api_key", "API key is required")
      {:error, :invalid_token} -> error(conn, :unauthorized, "invalid_api_key", "API key is invalid")
      {:error, :device_not_approved} -> error(conn, :forbidden, "device_not_approved", "Device is not approved")
    end
  end

  defp fetch_device(device_id) do
    case Devices.get_device(device_id) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, device} -> {:ok, device}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp authenticate(conn, device) do
    conn
    |> Map.get(:query_params, %{})
    |> Map.get("api_key")
    |> case do
      nil -> {:error, :missing_token}
      "" -> {:error, :missing_token}
      token -> Devices.authenticate_device(device, token)
    end
  end

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
