defmodule Nixstasis.Devices.FrpsToken do
  @moduledoc false

  @salt "nixstasis-frp-device-authorization-v1"
  # Slightly exceeds the client's one-hour FRP session so in-session reconnects remain valid.
  @max_age_seconds 3900

  def for_heartbeat(%{remote_access_requested: false}), do: nil

  def for_heartbeat(%{remote_access_requested: true, id: device_id} = device) do
    Phoenix.Token.sign(NixstasisWeb.Endpoint, @salt, %{
      "device_id" => to_string(device_id),
      "device_name" => device_name(device_id),
      "profile" => device.remote_access_profile || "default"
    })
  end

  def verify(token) when is_binary(token) and token != "" do
    Phoenix.Token.verify(NixstasisWeb.Endpoint, @salt, token, max_age: @max_age_seconds)
  end

  def verify(_token), do: {:error, :invalid}

  def device_name(device_id) do
    normalized =
      device_id
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/u, "")

    "atom-" <> normalized
  end
end
