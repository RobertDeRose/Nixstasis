defmodule NixstasisWeb.HeartbeatController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring
  alias NixstasisWeb.DeviceAuthentication
  alias NixstasisWeb.Plugs.RateLimiter

  def create(conn, %{"device_id" => device_id} = params) do
    with {:ok, device} <- fetch_device(device_id),
         :ok <- authenticate(conn, device),
         :ok <- RateLimiter.check_authenticated_device(device, :heartbeat) do
      case Monitoring.heartbeat(device, params) do
        {:ok, updated_device, commands} ->
          render(conn, :show, commands: commands, device: updated_device)

        {:error, {:telemetry_limits, _message}} ->
          conn
          |> put_status(413)
          |> json(%{
            error: %{
              code: "telemetry_limits_exceeded",
              message: "Telemetry exceeds the accepted persistence limits"
            }
          })

        {:error, _reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: %{code: "heartbeat_failed", message: "Heartbeat processing failed"}})
      end
    else
      {:error, :not_found} -> error(conn, :not_found, "device_not_found", "Device not found")
      {:error, :missing_token} -> error(conn, :unauthorized, "missing_api_key", "Bearer token is required")
      {:error, :invalid_token} -> error(conn, :unauthorized, "invalid_api_key", "Bearer token is invalid")
      {:error, :device_not_approved} -> error(conn, :forbidden, "device_not_approved", "Device is not approved")
      :limited -> RateLimiter.reject(conn)
    end
  end

  defp fetch_device(device_id) do
    case Devices.get_device(device_id) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, device} -> {:ok, device}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  defp authenticate(conn, device), do: DeviceAuthentication.authenticate(conn, device)

  defp error(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
