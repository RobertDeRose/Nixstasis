defmodule NixstasisWeb.DeviceCommandController do
  use NixstasisWeb, :controller

  alias Nixstasis.CommandAllowlists
  alias Nixstasis.Devices
  alias Nixstasis.Scripts
  alias NixstasisWeb.DeviceAuthentication
  alias NixstasisWeb.Plugs.RateLimiter

  def command_results(conn, %{"device_id" => device_id, "results" => results}) when is_list(results) do
    with {:ok, device} <- fetch_device(device_id),
         :ok <- authenticate(conn, device),
         :ok <- RateLimiter.check_authenticated_device(device, :command_results) do
      Scripts.ingest_command_results(device, results)
      CommandAllowlists.ingest_command_results(device, results)

      case Devices.acknowledge_command_results(device, results) do
        {:ok, count} ->
          conn
          |> put_status(:accepted)
          |> json(%{data: %{acknowledged_count: count}})

        {:error, _message} ->
          error(conn, :unprocessable_entity, "invalid_results", "results must be a list")
      end
    else
      {:error, :not_found} -> error(conn, :not_found, "device_not_found", "Device not found")
      {:error, :missing_token} -> error(conn, :unauthorized, "missing_api_key", "Bearer token is required")
      {:error, :invalid_token} -> error(conn, :unauthorized, "invalid_api_key", "Bearer token is invalid")
      {:error, :device_not_approved} -> error(conn, :forbidden, "device_not_approved", "Device is not approved")
      :limited -> RateLimiter.reject(conn)
    end
  end

  def command_results(conn, %{"device_id" => _device_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_request", message: "results must be a list"}})
  end

  def command_payload(conn, %{"device_id" => device_id, "ref" => ref}) do
    with {:ok, device} <- fetch_device(device_id),
         :ok <- authenticate(conn, device),
         :ok <- RateLimiter.check_authenticated_device(device, :command_payload) do
      case Devices.get_command_payload(device, ref) do
        {:ok, payload} -> json(conn, payload)
        {:error, :not_found} -> error(conn, :not_found, "payload_not_found", "Command payload not found")
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
