defmodule NixstasisWeb.OperatorContext do
  @moduledoc """
  Parses Caddy/AuthCrunch forwarded operator claims into application permissions.

  Caddy remains the production authorization edge. This module maps forwarded
  claims only after validating the dedicated Caddy-to-Phoenix proxy credential.
  """

  @role_capabilities %{
    "nixstasis/viewer" => %{
      "device_permissions" => %{"can_view" => true, "can_manage" => false, "can_remote_access" => false},
      "report_permissions" => %{"can_view" => true, "can_manage" => false},
      "alert_permissions" => %{"can_view" => true, "can_manage" => false},
      "settings_permissions" => %{"can_manage" => false},
      "script_permissions" => %{"can_view" => true, "can_manage" => false},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => false, "can_manage" => false}
    },
    "nixstasis/operator" => %{
      "device_permissions" => %{"can_view" => true, "can_manage" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true},
      "alert_permissions" => %{"can_view" => true, "can_manage" => true},
      "settings_permissions" => %{"can_manage" => false},
      "script_permissions" => %{"can_view" => true, "can_manage" => true},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => true, "can_manage" => true}
    },
    "nixstasis/admin" => %{
      "device_permissions" => %{"can_view" => true, "can_manage" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true},
      "alert_permissions" => %{"can_view" => true, "can_manage" => true},
      "settings_permissions" => %{"can_manage" => true},
      "script_permissions" => %{"can_view" => true, "can_manage" => true},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => true, "can_manage" => true}
    }
  }

  @proxy_auth_header "x-nixstasis-proxy-token"

  @device_scope_header "x-token-device-ids"

  @token_headers [
    "x-token-subject",
    "x-token-user-email",
    "x-token-user-name",
    "x-token-user-roles",
    @device_scope_header
  ]

  def from_conn(conn) do
    headers = Map.new(conn.req_headers)

    cond do
      token_claim_path?(headers) and trusted_proxy?(headers) -> from_trusted_headers(headers)
      token_claim_path?(headers) -> :error
      true -> fallback_context()
    end
  end

  def fallback_context do
    if local_development_fallback?() do
      :local_development
    else
      :error
    end
  end

  defp from_trusted_headers(headers) when is_map(headers) do
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
           "alert_permissions" => permissions["alert_permissions"],
           "settings_permissions" => permissions["settings_permissions"],
           "script_permissions" => permissions["script_permissions"],
           "command_policy_permissions" => permissions["command_policy_permissions"]
         }}

      :error ->
        :error
    end
  end

  def local_development_permissions do
    %{
      "device_permissions" => %{"can_view" => true, "can_manage" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true},
      "alert_permissions" => %{"can_view" => true, "can_manage" => true},
      "settings_permissions" => %{"can_manage" => true},
      "script_permissions" => %{"can_view" => true, "can_manage" => true},
      "command_policy_permissions" => %{"can_view_status" => true, "can_view_details" => true, "can_manage" => true}
    }
  end

  def fail_closed_permissions do
    %{
      "device_permissions" => %{"can_view" => false, "can_manage" => false, "can_remote_access" => false},
      "report_permissions" => %{"can_view" => false, "can_manage" => false},
      "alert_permissions" => %{"can_view" => false, "can_manage" => false},
      "settings_permissions" => %{"can_manage" => false},
      "script_permissions" => %{"can_view" => false, "can_manage" => false},
      "command_policy_permissions" => %{"can_view_status" => false, "can_view_details" => false, "can_manage" => false}
    }
  end

  defp token_claim_path?(headers) do
    Enum.any?(@token_headers, &Map.has_key?(headers, &1))
  end

  defp trusted_proxy?(headers) do
    expected = Application.get_env(:nixstasis, :proxy_auth_token)
    provided = Map.get(headers, @proxy_auth_header)

    if valid_proxy_token?(expected) and valid_proxy_token?(provided) do
      expected_digest = :crypto.hash(:sha256, expected)
      provided_digest = :crypto.hash(:sha256, provided)
      Plug.Crypto.secure_compare(expected_digest, provided_digest)
    else
      false
    end
  end

  defp valid_proxy_token?(token), do: is_binary(token) and byte_size(token) >= 32

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
      "alert_permissions" =>
        merge_capabilities(permissions["alert_permissions"], role_permissions["alert_permissions"]),
      "settings_permissions" =>
        merge_capabilities(permissions["settings_permissions"], role_permissions["settings_permissions"]),
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
    if Map.has_key?(headers, @device_scope_header) do
      headers
      |> Map.get(@device_scope_header)
      |> normalize_claim_values()
    end
  end

  defp scope_device_permissions(permissions, nil), do: permissions

  defp scope_device_permissions(permissions, device_ids) do
    update_in(permissions, ["device_permissions"], &Map.put(&1, "device_ids", device_ids))
  end
end
