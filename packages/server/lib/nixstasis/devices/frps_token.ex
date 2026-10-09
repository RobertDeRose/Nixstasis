defmodule Nixstasis.Devices.FrpsToken do
  @moduledoc false

  alias Nixstasis.Devices.RemoteAccess

  @salt "nixstasis-frp-lease-authorization-v2"
  @max_age_seconds 3900

  def for_heartbeat(device) do
    case credential_for_heartbeat(device) do
      nil -> nil
      {token, _expires_at_ms} -> token
    end
  end

  def credential_for_heartbeat(device) do
    case authorization_for_heartbeat(device) do
      nil -> nil
      data -> {data.remote_access_token, data.remote_access_expires_at_ms}
    end
  end

  def authorization_for_heartbeat(%{id: device_id}) do
    case RemoteAccess.selected(device_id) do
      nil ->
        nil

      lease ->
        expires_at_ms =
          min(
            DateTime.to_unix(lease.expires_at, :millisecond),
            (System.system_time(:second) + @max_age_seconds) * 1000
          )

        token =
          Phoenix.Token.sign(NixstasisWeb.Endpoint, @salt, %{
            "device_id" => device_id,
            "device_name" => device_name(device_id),
            "lease_id" => lease.id,
            "profile" => lease.profile,
            "expires_at_ms" => expires_at_ms
          })

        %{
          remote_access_token: token,
          remote_access_expires_at_ms: expires_at_ms,
          remote_access_lease_id: lease.id,
          remote_access_profile: %{name: lease.profile, version: 1}
        }
    end
  end

  def verify(token) when is_binary(token) and token != "" do
    with {:ok, claims} when is_map(claims) <-
           Phoenix.Token.verify(NixstasisWeb.Endpoint, @salt, token, max_age: @max_age_seconds),
         true <- unexpired?(claims["expires_at_ms"]) do
      lease_id = claims["lease_id"]
      profile = claims["profile"]

      case RemoteAccess.selected(claims["device_id"]) do
        %{id: ^lease_id, profile: ^profile, expires_at: expiry} ->
          if claims["expires_at_ms"] <= DateTime.to_unix(expiry, :millisecond),
            do: {:ok, claims},
            else: {:error, :inactive_authorization}

        _ ->
          {:error, :inactive_authorization}
      end
    else
      false -> {:error, :expired}
      {:ok, _} -> {:error, :invalid}
      {:error, _reason} = error -> error
    end
  end

  def verify(_token), do: {:error, :invalid}

  defp unexpired?(expires_at) when is_integer(expires_at), do: expires_at > System.system_time(:millisecond)
  defp unexpired?(_expires_at), do: false

  def device_name(device_id) do
    normalized = device_id |> to_string() |> String.downcase() |> String.replace(~r/[^a-z0-9]/u, "")
    "atom-" <> normalized
  end
end
