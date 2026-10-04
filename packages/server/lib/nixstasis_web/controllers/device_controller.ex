defmodule NixstasisWeb.DeviceController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions

  action_fallback(NixstasisWeb.FallbackController)

  def index(conn, params) do
    with {:ok, actor} <- device_list_actor(conn) do
      json(conn, Devices.runtime_list(params, actor: actor))
    end
  end

  def register(conn, device_params) do
    with {:ok, payload} <- Devices.register_runtime_device(device_params) do
      conn
      |> put_status(:created)
      |> json(payload)
    end
  end

  defp device_list_actor(conn) do
    context =
      case OperatorContext.from_conn(conn) do
        {:ok, context} -> context
        :local_development -> OperatorContext.local_development_permissions()
        :error -> nil
      end

    case Permissions.device_data_actor(context) do
      {:ok, actor} -> {:ok, actor}
      {:error, _reason} -> {:error, :forbidden}
    end
  end
end
