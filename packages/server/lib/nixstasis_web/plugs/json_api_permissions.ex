defmodule NixstasisWeb.Plugs.JsonApiPermissions do
  @moduledoc """
  Enforces operator role permissions for Ash JSON:API routes.

  Device runtime APIs live under `/api/v1` and use device credentials instead of
  AuthCrunch operator claims. The generated `/api/json` surface is an
  operator/developer resource API and must fail closed outside local dev/test
  fallback. Verified operator requests also receive an Ash actor so device-backed
  reads can enforce row scope and alert-rule actions can enforce view/manage
  capabilities in the resource layer.
  """

  import Plug.Conn

  alias Nixstasis.Devices
  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions
  alias NixstasisWeb.Plugs.RateLimiter

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case policy_for(conn) do
      :device_runtime_registration ->
        conn

      :device_runtime_list ->
        authorize_operator(conn, {:device, :view})

      {:device_runtime, device_id} ->
        authenticate_device_runtime(conn, device_id)

      policy ->
        authorize_operator(conn, policy)
    end
  end

  defp authorize_operator(conn, policy) do
    context = context_from_conn(conn)

    if permitted?(context, policy) do
      case operator_actor(context) do
        {:ok, actor} -> Ash.PlugHelpers.set_actor(conn, actor)
        {:error, :invalid_device_scope} -> forbidden(conn)
      end
    else
      forbidden(conn)
    end
  end

  defp policy_for(%{path_info: ["api", "json", "device_runtime", "devices", "register"], method: "POST"}),
    do: :device_runtime_registration

  defp policy_for(%{path_info: ["api", "json", "device_runtime", "devices"], method: method})
       when method in ["GET", "HEAD", "OPTIONS"],
       do: :device_runtime_list

  defp policy_for(%{path_info: ["api", "json", "device_runtime", "devices", device_id | _]}) do
    {:device_runtime, device_id}
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

  defp policy_for(%{path_info: ["api", "json", "alerts" | _], method: method}) do
    if method in ["GET", "HEAD", "OPTIONS"], do: {:device, :view}, else: {:device, :manage_all}
  end

  defp policy_for(%{path_info: ["api", "json", "alert_rules" | _], method: method}) do
    if method in ["GET", "HEAD", "OPTIONS"], do: {:alert, :view}, else: {:alert, :manage}
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

  defp operator_actor(context) when is_map(context) do
    device_permissions = Map.get(context, "device_permissions", %{})
    alert_permissions = Map.get(context, "alert_permissions", %{})

    with {:ok, authorized_device_ids} <-
           validated_device_scope(Permissions.authorized_device_ids(device_permissions)) do
      {:ok,
       %{
         can_view_device_data: Permissions.can_view_device_details?(device_permissions),
         unscoped_device_access: is_nil(authorized_device_ids),
         authorized_device_ids: authorized_device_ids || [],
         can_view_alert_rules: alert_permissions["can_view"] == true,
         can_manage_alert_rules: alert_permissions["can_manage"] == true
       }}
    end
  end

  defp validated_device_scope(nil), do: {:ok, nil}

  defp validated_device_scope(%MapSet{} = ids) do
    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, valid_ids} ->
      case Ecto.UUID.cast(id) do
        {:ok, valid_id} -> {:cont, {:ok, [valid_id | valid_ids]}}
        :error -> {:halt, {:error, :invalid_device_scope}}
      end
    end)
    |> case do
      {:ok, valid_ids} -> {:ok, Enum.reverse(valid_ids)}
      error -> error
    end
  end

  defp validated_device_scope(_ids), do: {:error, :invalid_device_scope}

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

  defp permitted?(context, {:alert, :view}) do
    get_in(context, ["alert_permissions", "can_view"]) == true
  end

  defp permitted?(context, {:alert, :manage}) do
    get_in(context, ["alert_permissions", "can_manage"]) == true
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

  defp authenticate_device_runtime(conn, device_id) do
    case Devices.get_device(device_id) do
      {:ok, nil} ->
        runtime_error(conn, :not_found, "device_not_found", "Device not found")

      {:ok, device} ->
        case Map.get(conn.query_params || %{}, "api_key") do
          nil -> runtime_error(conn, :unauthorized, "missing_api_key", "API key is required")
          "" -> runtime_error(conn, :unauthorized, "missing_api_key", "API key is required")
          token -> authenticate_device_runtime(conn, device, token)
        end

      {:error, _reason} ->
        runtime_error(conn, :not_found, "device_not_found", "Device not found")
    end
  end

  defp authenticate_device_runtime(conn, device, token) do
    case Devices.authenticate_device(device, token) do
      :ok ->
        case device_runtime_rate_action(conn) do
          nil ->
            put_device_runtime_actor(conn, device)

          action ->
            case RateLimiter.check_authenticated_device(device, action) do
              :ok -> put_device_runtime_actor(conn, device)
              :limited -> runtime_error(conn, :too_many_requests, "rate_limited", "Rate limit exceeded")
            end
        end

      {:error, :device_not_approved} ->
        runtime_error(conn, :forbidden, "device_not_approved", "Device is not approved")

      {:error, :invalid_token} ->
        runtime_error(conn, :unauthorized, "invalid_api_key", "API key is invalid")

      {:error, :missing_token} ->
        runtime_error(conn, :unauthorized, "missing_api_key", "API key is required")
    end
  end

  defp put_device_runtime_actor(conn, device) do
    conn
    |> Ash.PlugHelpers.set_actor(device)
    |> Ash.PlugHelpers.set_context(%{device: device})
  end

  defp device_runtime_rate_action(%{
         method: "POST",
         path_info: ["api", "json", "device_runtime", "devices", _id, "heartbeat"]
       }),
       do: :heartbeat

  defp device_runtime_rate_action(%{
         method: "POST",
         path_info: ["api", "json", "device_runtime", "devices", _id, "command_results"]
       }),
       do: :command_results

  defp device_runtime_rate_action(%{
         method: "GET",
         path_info: ["api", "json", "device_runtime", "devices", _id, "command_payloads", _ref]
       }),
       do: :command_payload

  defp device_runtime_rate_action(_conn), do: nil

  defp runtime_error(conn, status, code, detail) do
    conn
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(status, Jason.encode!(%{errors: [%{code: code, detail: detail}]}))
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/vnd.api+json")
    |> send_resp(:forbidden, Jason.encode!(%{errors: [%{code: "forbidden", detail: "JSON:API access is forbidden"}]}))
    |> halt()
  end
end
