defmodule NixstasisWeb.Plugs.JsonApiPermissions do
  @moduledoc """
  Enforces operator role permissions for Ash JSON:API routes.

  Device runtime APIs live under `/api/v1` and use device credentials instead of
  AuthCrunch operator claims. The generated `/api/json` surface is an
  operator/developer resource API and must fail closed outside local dev/test
  fallback.
  """

  import Plug.Conn

  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    policy = policy_for(conn)

    conn
    |> context_from_conn()
    |> permitted?(policy)
    |> case do
      true -> conn
      false -> forbidden(conn)
    end
  end

  defp policy_for(%{path_info: ["api", "json", "devices" | rest], method: method}) do
    case {method, rest} do
      {method, _} when method in ["GET", "HEAD", "OPTIONS"] -> {:device, :view}
      {"POST", _} -> {:device, :create}
      {method, [id | _]} when method in ["PATCH", "DELETE"] -> {:device, {:manage, id}}
      _ -> {:device, :manage_all}
    end
  end

  defp policy_for(%{path_info: ["api", "json", "pending_commands" | _], method: method}) do
    if method in ["GET", "HEAD", "OPTIONS"], do: {:device, :view}, else: {:device, :manage_all}
  end

  defp policy_for(%{path_info: ["api", "json", "telemetry_events" | _], method: method}) do
    if method in ["GET", "HEAD", "OPTIONS"], do: {:device, :view}, else: {:device, :manage_all}
  end

  defp policy_for(%{path_info: ["api", "json", "system_settings" | _]}), do: {:role, "nixstasis/admin"}

  defp policy_for(%{path_info: ["api", "json", "builder_contract" | _]}), do: {:report, :view}
  defp policy_for(%{path_info: ["api", "json", "swaggerui" | _]}), do: {:report, :view}
  defp policy_for(%{path_info: ["api", "json", "open_api"]}), do: {:report, :view}

  defp policy_for(%{path_info: ["api", "json" | _], method: method}) do
    if method in ["GET", "HEAD", "OPTIONS"], do: {:report, :view}, else: {:report, :manage}
  end

  defp context_from_conn(conn) do
    case OperatorContext.from_conn(conn) do
      {:ok, context} -> context
      :local_development -> Map.put(OperatorContext.local_development_permissions(), "roles", ["nixstasis/admin"])
      :error -> nil
    end
  end

  defp permitted?(nil, _policy), do: false

  defp permitted?(context, {:device, :view}) do
    context |> Map.get("device_permissions") |> Permissions.can_view_device_details?()
  end

  defp permitted?(context, {:device, :create}) do
    context |> Map.get("device_permissions") |> Permissions.can_create_devices?()
  end

  defp permitted?(context, {:device, {:manage, id}}) do
    context |> Map.get("device_permissions") |> Permissions.can_manage_device?(id)
  end

  defp permitted?(context, {:device, :manage_all}) do
    context |> Map.get("device_permissions") |> Permissions.can_manage_all_devices?()
  end

  defp permitted?(context, {:report, :view}) do
    get_in(context, ["report_permissions", "can_view"]) == true
  end

  defp permitted?(context, {:report, :manage}) do
    get_in(context, ["report_permissions", "can_manage"]) == true
  end

  defp permitted?(context, {:role, role}) do
    role in Map.get(context, "roles", [])
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(:forbidden, Jason.encode!(%{errors: [%{code: "forbidden", detail: "JSON:API access is forbidden"}]}))
    |> halt()
  end
end
