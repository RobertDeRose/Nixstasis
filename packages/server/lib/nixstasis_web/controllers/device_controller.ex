defmodule NixstasisWeb.DeviceController do
  use NixstasisWeb, :controller

  alias Nixstasis.Devices
  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions

  action_fallback(NixstasisWeb.FallbackController)

  @doc """
  Returns the compatibility device list for an authenticated operator.

  Requires device-view permission and passes a trusted read actor to the Devices
  context so query filters cannot bypass row scope. Missing authentication
  returns 401; missing permission or malformed scope returns 403. Successful
  responses retain the runtime list's `data` and active-filter metadata.
  """
  def index(conn, params) do
    with {:ok, context} <- operator_context(conn),
         true <- Permissions.can_view_device_details?(Permissions.device_permissions(context)),
         {:ok, actor} <- Permissions.device_read_actor(context) do
      json(conn, Devices.runtime_list(params, actor: actor))
    else
      {:error, :unauthorized} -> send_resp(conn, :unauthorized, "")
      {:error, :invalid_device_scope} -> send_resp(conn, :forbidden, "")
      false -> send_resp(conn, :forbidden, "")
    end
  end

  # Resolve proxy-authenticated permissions, or the explicitly enabled local
  # fallback. Convert all other authentication failures into the controller's 401.
  defp operator_context(conn) do
    case OperatorContext.from_conn(conn) do
      {:ok, context} -> {:ok, context}
      :local_development -> {:ok, OperatorContext.local_development_permissions()}
      :error -> {:error, :unauthorized}
    end
  end

  def register(conn, device_params) do
    with {:ok, payload} <- Devices.register_runtime_device(device_params) do
      conn
      |> put_status(:created)
      |> json(payload)
    end
  end
end
