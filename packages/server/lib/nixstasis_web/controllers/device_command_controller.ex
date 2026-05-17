defmodule NixstasisWeb.DeviceCommandController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices

  def command_results(conn, %{"device_id" => device_id, "results" => results}) when is_list(results) do
    with {:ok, device} <- fetch_device(device_id),
         :ok <- authenticate(conn, device) do
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
      {:error, :missing_token} -> error(conn, :unauthorized, "missing_api_key", "API key is required")
      {:error, :invalid_token} -> error(conn, :unauthorized, "invalid_api_key", "API key is invalid")
      {:error, :device_not_approved} -> error(conn, :forbidden, "device_not_approved", "Device is not approved")
    end
  end

  def command_results(conn, %{"device_id" => _device_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_request", message: "results must be a list"}})
  end

  def command_payload(conn, %{"device_id" => device_id, "ref" => ref}) do
    with {:ok, device} <- fetch_device(device_id),
         :ok <- authenticate(conn, device) do
      case Devices.get_command_payload(device, ref) do
        {:ok, payload} -> json(conn, payload)
        {:error, :not_found} -> error(conn, :not_found, "payload_not_found", "Command payload not found")
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
