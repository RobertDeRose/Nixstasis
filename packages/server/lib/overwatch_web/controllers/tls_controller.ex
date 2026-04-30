defmodule NixstasisWeb.TLSController do
  use NixstasisWeb, :controller

  alias Nixstasis.Deployment
  require Logger

  def check_domain(conn, %{"domain" => domain}) do
    if Deployment.approved_tls_domain?(domain) do
      approve(conn, domain)
    else
      deny(conn, domain)
    end
  end

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
