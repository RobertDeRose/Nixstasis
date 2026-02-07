defmodule NixstasisWeb.TLSController do
  use NixstasisWeb, :controller
  import Nixstasis.Utilities, only: [format_mac_address: 1]

  alias Nixstasis.Devices
  require Logger

  # Compiled once at load time
  @domain_pattern ~r/^(auth|frp-router|atom-.*?)\.ab\.test-device\.com$/

  def check_domain(conn, %{"domain" => domain}) do
    case Regex.run(@domain_pattern, domain) do
      [_, type] when type in ["auth", "frp-router"] -> approve(conn, domain)

      [_, subdomain] -> if valid_subdomain?(subdomain), do: approve(conn, domain), else: deny(conn, domain)

      _ -> deny(conn, domain)
    end
  end

  defp valid_subdomain?("atom-" <> subdomain) do
    subdomain |> format_mac_address() |> Devices.requesting_remote_access?()
  end

  defp valid_subdomain?(_), do: false

  defp approve(conn, domain) do
    Logger.info("[APPROVING] #{domain} for TLS")
    # Returns 204 No Content
    send_resp(conn, :no_content, "")
  end

  defp deny(conn, domain) do
    Logger.info("[DENYING] #{domain} for TLS")
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "The host is not permitted"})
  end
end
