defmodule NixstasisWeb.Plugs.DevicePermissions do
  @moduledoc """
  Populates browser session permissions for LiveView authorization.

  Production Caddy/AuthCrunch requests are mapped from trusted forwarded claims.
  Requests without AuthCrunch claim headers keep permissive local-development
  defaults.
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case NixstasisWeb.OperatorContext.from_conn(conn) do
      {:ok, operator_context} ->
        conn
        |> put_session("operator_context", Map.drop(operator_context, ["device_permissions", "report_permissions"]))
        |> put_permissions(operator_context)

      :error ->
        Logger.warning("AuthCrunch browser claim headers were present but no valid Nixstasis role was found")

        conn
        |> put_session("operator_context", %{"authcrunch_claim_error" => true})
        |> put_permissions(NixstasisWeb.OperatorContext.fail_closed_permissions())

      :local_development ->
        put_default_permissions(conn)
    end
  end

  defp put_default_permissions(conn) do
    case get_session(conn, "device_permissions") do
      permissions when is_map(permissions) ->
        conn

      _ ->
        put_permissions(conn, NixstasisWeb.OperatorContext.local_development_permissions())
    end
  end

  defp put_permissions(conn, permissions) do
    Enum.reduce(permissions, conn, fn {key, value}, conn -> put_session(conn, key, value) end)
  end
end
