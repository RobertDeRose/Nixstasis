defmodule NixstasisWeb.Plugs.JsonApiPermissions do
  @moduledoc """
  Enforces role-derived permissions for JSON:API routes that need app-level auth.
  """

  import Plug.Conn

  alias NixstasisWeb.OperatorContext

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{request_path: path} = conn, _opts) do
    if alert_rules_path?(path) do
      authorize_alert_rules(conn)
    else
      conn
    end
  end

  defp alert_rules_path?(path),
    do: path == "/api/json/alert_rules" or String.starts_with?(path, "/api/json/alert_rules/")

  defp authorize_alert_rules(conn) do
    conn
    |> permissions_from_conn()
    |> permitted?(conn.method)
    |> case do
      true -> conn
      false -> forbidden(conn)
    end
  end

  defp permissions_from_conn(conn) do
    case OperatorContext.from_conn(conn) do
      {:ok, context} -> context["report_permissions"] || %{}
      :local_development -> OperatorContext.local_development_permissions()["report_permissions"]
      :error -> %{}
    end
  end

  defp permitted?(permissions, method) when method in ["GET", "HEAD"], do: permissions["can_view"] == true

  defp permitted?(permissions, _method), do: permissions["can_manage"] == true

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(:forbidden, Jason.encode!(%{errors: [%{code: "forbidden", detail: "Alert-rule access is forbidden"}]}))
    |> halt()
  end
end
