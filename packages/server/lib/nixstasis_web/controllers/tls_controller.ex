defmodule NixstasisWeb.TLSController do
  use NixstasisWeb, :controller

  alias Nixstasis.Deployment
  alias Nixstasis.TLSObservations
  require Logger

  def check_domain(conn, %{"domain" => domain}) do
    approved? = Deployment.approved_tls_domain?(domain)
    record_observation(domain, approved?)

    if approved? do
      approve(conn, domain)
    else
      deny(conn, domain)
    end
  end

  def observations(conn, _params) do
    if TLSObservations.enabled?() and authorized_observation_request?(conn) do
      json(conn, %{data: TLSObservations.list()})
    else
      send_resp(conn, :not_found, "")
    end
  end

  def clear_observations(conn, _params) do
    if TLSObservations.enabled?() and authorized_observation_request?(conn) do
      TLSObservations.clear()
      send_resp(conn, :no_content, "")
    else
      send_resp(conn, :not_found, "")
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

  defp record_observation(domain, approved?) do
    TLSObservations.record(domain, approved?)
  end

  defp authorized_observation_request?(conn) do
    configured_token = System.get_env("NIXSTASIS_TLS_OBSERVATIONS_TOKEN")
    provided_token = get_req_header(conn, "x-nixstasis-tls-observations-token") |> List.first()

    is_binary(configured_token) and configured_token != "" and
      is_binary(provided_token) and Plug.Crypto.secure_compare(configured_token, provided_token)
  end
end
