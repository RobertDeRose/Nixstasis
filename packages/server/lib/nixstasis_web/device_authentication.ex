defmodule NixstasisWeb.DeviceAuthentication do
  @moduledoc """
  Authenticates managed-device runtime requests using an Authorization bearer token.

  Device credentials are intentionally accepted only from the request header so
  reusable tokens never enter request URLs, proxy request-target metadata, or
  ordinary query-string logs.
  """

  import Plug.Conn, only: [get_req_header: 2]

  alias Nixstasis.Devices

  @spec authenticate(Plug.Conn.t(), map()) :: :ok | {:error, :missing_token | :invalid_token | :device_not_approved}
  def authenticate(conn, device) do
    with {:ok, token} <- bearer_token(conn) do
      Devices.authenticate_device(device, token)
    end
  end

  @spec bearer_token(Plug.Conn.t()) :: {:ok, String.t()} | {:error, :missing_token | :invalid_token}
  def bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [] ->
        {:error, :missing_token}

      [header] ->
        parse_bearer(header)

      _headers ->
        {:error, :invalid_token}
    end
  end

  defp parse_bearer(header) when is_binary(header) do
    case String.split(header, ~r/\s+/, parts: 2, trim: true) do
      [scheme, token] when token != "" ->
        if String.downcase(scheme) == "bearer",
          do: {:ok, token},
          else: {:error, :invalid_token}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp parse_bearer(_header), do: {:error, :invalid_token}
end
