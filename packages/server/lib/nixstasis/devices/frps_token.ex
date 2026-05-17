defmodule Nixstasis.Devices.FrpsToken do
  @moduledoc false

  require Logger

  def for_heartbeat(%{remote_access_requested: false}), do: nil

  def for_heartbeat(%{remote_access_requested: true, id: device_id}) do
    case System.get_env("FRPS_AUTH_TOKEN") do
      token when is_binary(token) and token != "" ->
        if String.trim(token) == "" do
          log_missing_token(device_id)
          nil
        else
          token
        end

      _ ->
        log_missing_token(device_id)
        nil
    end
  end

  defp log_missing_token(device_id) do
    Logger.error("FRPS_AUTH_TOKEN is missing while remote access is requested", device_id: device_id)
  end
end
