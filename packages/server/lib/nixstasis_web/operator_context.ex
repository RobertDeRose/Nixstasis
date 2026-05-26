defmodule NixstasisWeb.OperatorContext do
  @moduledoc """
  Parses Caddy/AuthCrunch forwarded operator claims into application permissions.

  Caddy remains the production authorization edge. This module only maps trusted
  forwarded claims into LiveView capability maps after Caddy admits a request.
  """

  @role_capabilities %{
    "nixstasis/viewer" => %{
      "device_permissions" => %{"can_view" => true, "can_remote_access" => false},
      "report_permissions" => %{"can_view" => true, "can_manage" => false}
    },
    "nixstasis/operator" => %{
      "device_permissions" => %{"can_view" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true}
    },
    "nixstasis/admin" => %{
      "device_permissions" => %{"can_view" => true, "can_remote_access" => true},
      "report_permissions" => %{"can_view" => true, "can_manage" => true}
    }
  }

  @token_headers [
    "x-token-subject",
    "x-token-user-email",
    "x-token-user-name",
    "x-token-user-roles"
  ]

  def from_conn(conn) do
    headers = Map.new(conn.req_headers)

    if token_claim_path?(headers) do
      from_headers(headers)
    else
      :local_development
    end
  end

  def from_headers(headers) when is_map(headers) do
    roles = headers |> Map.get("x-token-user-roles") |> normalize_claim_values()

    case permissions_for_roles(roles) do
      {:ok, permissions} ->
        {:ok,
         %{
           "subject" => Map.get(headers, "x-token-subject"),
           "email" => Map.get(headers, "x-token-user-email"),
           "name" => Map.get(headers, "x-token-user-name"),
           "roles" => roles,
           "device_permissions" => permissions["device_permissions"],
           "report_permissions" => permissions["report_permissions"]
         }}

      :error ->
        :error
    end
  end

  def from_headers(_headers), do: :error

  def local_development_permissions do
    %{
      "device_permissions" => %{"can_view" => true, "can_remote_access" => true}
    }
  end

  def fail_closed_permissions do
    %{
      "device_permissions" => %{"can_view" => false, "can_remote_access" => false},
      "report_permissions" => %{"can_view" => false, "can_manage" => false}
    }
  end

  defp token_claim_path?(headers) do
    Enum.any?(@token_headers, &Map.has_key?(headers, &1))
  end

  defp permissions_for_roles([]), do: :error

  defp permissions_for_roles(roles) do
    known_roles = Enum.filter(roles, &Map.has_key?(@role_capabilities, &1))

    if known_roles == [] do
      :error
    else
      {:ok, Enum.reduce(known_roles, fail_closed_permissions(), &merge_role_permissions/2)}
    end
  end

  defp merge_role_permissions(role, permissions) do
    role_permissions = Map.fetch!(@role_capabilities, role)

    %{
      "device_permissions" => Map.merge(permissions["device_permissions"], role_permissions["device_permissions"]),
      "report_permissions" => Map.merge(permissions["report_permissions"], role_permissions["report_permissions"])
    }
  end

  defp normalize_claim_values(value) when is_binary(value) do
    value
    |> String.split([",", " "], trim: true)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp normalize_claim_values(_value), do: []
end
