defmodule NixstasisWeb.DeviceCommandController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices

  def command_results(conn, %{"device_id" => device_id, "results" => results}) when is_list(results) do
    device = Devices.get_device!(device_id)

    case Devices.acknowledge_command_results(device, results) do
      {:ok, count} ->
        conn
        |> put_status(:accepted)
        |> json(%{data: %{acknowledged_count: count}})

      {:error, message} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: %{code: "invalid_request", message: message}})
    end
  end

  def command_results(conn, %{"device_id" => _device_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: %{code: "invalid_request", message: "results must be a list"}})
  end

  def command_payload(conn, %{"device_id" => device_id, "ref" => ref}) do
    device = Devices.get_device!(device_id)

    case Devices.get_command_payload(device, ref) do
      {:ok, payload} ->
        json(conn, payload)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "")
    end
  end
end
