defmodule Nixstasis.Devices.FrpsToken do
  @moduledoc false

  alias Nixstasis.Devices

  @salt "nixstasis-frp-device-authorization-v1"
  # Defense-in-depth outer bound; every token also carries the lease's absolute expiry.
  @max_age_seconds 3900

  def for_heartbeat(device) do
    case credential_for_heartbeat(device) do
      nil -> nil
      {token, _expires_at_ms} -> token
    end
  end

  def credential_for_heartbeat(%{id: device_id} = device) do
    if Devices.remote_access_active?(device) do
      expires_at_ms =
        min(
          DateTime.to_unix(device.remote_access_expires_at, :millisecond),
          (System.system_time(:second) + @max_age_seconds) * 1000
        )

      token =
        Phoenix.Token.sign(NixstasisWeb.Endpoint, @salt, %{
          "device_id" => to_string(device_id),
          "device_name" => device_name(device_id),
          "profile" => device.remote_access_profile || "default",
          "expires_at_ms" => expires_at_ms
        })

      {token, expires_at_ms}
    end
  end

  def verify(token) when is_binary(token) and token != "" do
    with {:ok, claims} <- Phoenix.Token.verify(NixstasisWeb.Endpoint, @salt, token, max_age: @max_age_seconds),
         true <- unexpired?(claims["expires_at_ms"]) do
      {:ok, claims}
    else
      false -> {:error, :expired}
      {:error, _reason} = error -> error
    end
  end

  def verify(_token), do: {:error, :invalid}

  defp unexpired?(expires_at) when is_integer(expires_at), do: expires_at > System.system_time(:millisecond)
  defp unexpired?(_expires_at), do: false

  def device_name(device_id) do
    normalized =
      device_id
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/u, "")

    "atom-" <> normalized
  end
end
