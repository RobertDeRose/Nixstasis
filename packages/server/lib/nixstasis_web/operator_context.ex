defmodule NixstasisWeb.OperatorContext do
  @moduledoc """
  Parses Caddy/AuthCrunch forwarded operator claims into application permissions.

  Caddy remains the production authorization edge. This module only maps trusted
  forwarded claims into LiveView capability maps after Caddy admits a request.
  """

  @role_capabilities %{
    "nixstasis/viewer" => %{
      "device_permissions" => %{"can_view" => true, "can_manage" => false, "can_remote_access" => false},
      "report_permissions" => %{"can_view" => true, "can_manage" => false},
      "script_permissions" => %{"can_view" => true, "can_manage" => false},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => false, "can_manage" => false}
    },
    "nixstasis/operator" => %{
      "device_permissions" => %{"can_view" => true, "can_manage" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true},
      "script_permissions" => %{"can_view" => true, "can_manage" => true},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => true, "can_manage" => true}
    },
    "nixstasis/admin" => %{
      "device_permissions" => %{"can_view" => true, "can_manage" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true},
      "script_permissions" => %{"can_view" => true, "can_manage" => true},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => true, "can_manage" => true}
    }
  }

  @token_headers [
    "x-token-subject",
    "x-token-user-email",
    "x-token-user-name",
    "x-token-user-roles",
    "x-token-device-id",
    "x-token-device-ids",
    "x-token-allowed-device-ids"
  ]

  def from_conn(conn) do
    headers = Map.new(conn.req_headers)

    if token_claim_path?(headers) do
      from_headers(headers)
    else
      fallback_context()
    end
  end

  def fallback_context do
    if local_development_fallback?() do
      :local_development
    else
      :error
    end
  end

  def from_headers(headers) when is_map(headers) do
    roles = headers |> Map.get("x-token-user-roles") |> normalize_claim_values()

    device_ids = device_scope_from_headers(headers)

    case permissions_for_roles(roles, device_ids) do
      {:ok, permissions} ->
        {:ok,
         %{
           "subject" => Map.get(headers, "x-token-subject"),
           "email" => Map.get(headers, "x-token-user-email"),
           "name" => Map.get(headers, "x-token-user-name"),
           "roles" => roles,
           "device_permissions" => permissions["device_permissions"],
           "report_permissions" => permissions["report_permissions"],
           "script_permissions" => permissions["script_permissions"],
           "command_policy_permissions" => permissions["command_policy_permissions"]
         }}

      :error ->
        :error
    end
  end

  def from_headers(_headers), do: :error

  def local_development_permissions do
    %{
      "device_permissions" => %{"can_view" => true, "can_manage" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true},
      "script_permissions" => %{"can_view" => true, "can_manage" => true},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => true, "can_manage" => true}
    }
  end

  def fail_closed_permissions do
    %{
      "device_permissions" => %{"can_view" => false, "can_manage" => false, "can_remote_access" => false},
      "report_permissions" => %{"can_view" => false, "can_manage" => false},
      "script_permissions" => %{"can_view" => false, "can_manage" => false},
      "command_policy_permissions" => %{"can_view_status" => false, "can_view_details" => false, "can_manage" => false}
    }
  end

  defp token_claim_path?(headers) do
    Enum.any?(@token_headers, &Map.has_key?(headers, &1))
  end

  defp local_development_fallback? do
    Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
  end

  defp permissions_for_roles([], _device_ids), do: :error

  defp permissions_for_roles(roles, device_ids) do
    known_roles = Enum.filter(roles, &Map.has_key?(@role_capabilities, &1))

    if known_roles == [] do
      :error
    else
      permissions =
        known_roles
        |> Enum.reduce(fail_closed_permissions(), &merge_role_permissions/2)
        |> scope_device_permissions(device_ids)

      {:ok, permissions}
    end
  end

  defp merge_role_permissions(role, permissions) do
    role_permissions = Map.fetch!(@role_capabilities, role)

    %{
      "device_permissions" =>
        merge_capabilities(permissions["device_permissions"], role_permissions["device_permissions"]),
      "report_permissions" =>
        merge_capabilities(permissions["report_permissions"], role_permissions["report_permissions"]),
      "script_permissions" =>
        merge_capabilities(permissions["script_permissions"], role_permissions["script_permissions"]),
      "command_policy_permissions" =>
        merge_capabilities(permissions["command_policy_permissions"], role_permissions["command_policy_permissions"])
    }
  end

  defp merge_capabilities(current, incoming) do
    Map.merge(current, incoming, fn _key, left, right -> left == true or right == true end)
  end

  defp normalize_claim_values(value) when is_binary(value) do
    value
    |> String.split([",", " "], trim: true)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp normalize_claim_values(_value), do: []

  defp device_scope_from_headers(headers) do
    [
      Map.get(headers, "x-token-device-id"),
      Map.get(headers, "x-token-device-ids"),
      Map.get(headers, "x-token-allowed-device-ids")
    ]
    |> Enum.flat_map(&normalize_claim_values/1)
    |> Enum.uniq()
  end

  defp scope_device_permissions(permissions, []), do: permissions

  defp scope_device_permissions(permissions, device_ids) do
    update_in(permissions, ["device_permissions"], &Map.put(&1, "device_ids", device_ids))
  end
end
