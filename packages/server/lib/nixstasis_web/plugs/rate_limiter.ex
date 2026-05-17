defmodule NixstasisWeb.Plugs.RateLimiter do
  @moduledoc false

  import Plug.Conn

  @default_limit 120
  @heartbeat_limit 30
  @default_window_ms 60_000

  def init(opts), do: opts

  def call(conn, opts) do
    if rate_limited_request?(conn) do
      key = rate_limit_key(conn)
      limit = request_limit(conn, opts)
      window_ms = rate_limit(opts, :window_ms, @default_window_ms)

      case NixstasisWeb.RateLimiterStore.check_rate(key, limit, window_ms) do
        :ok ->
          conn

        :limited ->
          conn
          |> put_status(:too_many_requests)
          |> Phoenix.Controller.json(%{error: %{code: "rate_limited", message: "Rate limit exceeded"}})
          |> halt()
      end
    else
      conn
    end
  end

  defp heartbeat_request?(%{method: "POST", path_info: ["api", "v1", "devices", _id, "heartbeat"]}), do: true
  defp heartbeat_request?(_conn), do: false

  defp rate_limited_request?(%{path_info: ["api", "json" | _]}), do: true
  defp rate_limited_request?(%{path_info: ["api", "v1" | _]}), do: true
  defp rate_limited_request?(conn), do: heartbeat_request?(conn)

  defp request_limit(conn, opts) do
    if heartbeat_request?(conn),
      do: rate_limit(opts, :limit, @heartbeat_limit),
      else: rate_limit(opts, :limit, @default_limit)
  end

  defp rate_limit_key(conn) do
    identity = conn.path_params["device_id"] || heartbeat_device_id(conn) || remote_ip(conn)
    {:api, conn.method, identity}
  end

  defp heartbeat_device_id(%{path_params: %{"device_id" => device_id}}), do: device_id
  defp heartbeat_device_id(%{path_info: ["api", "v1", "devices", device_id, "heartbeat"]}), do: device_id
  defp heartbeat_device_id(_conn), do: nil

  defp remote_ip(conn), do: conn.remote_ip |> :inet.ntoa() |> to_string()

  defp rate_limit(opts, key, default) do
    app_config = Application.get_env(:nixstasis, :rate_limit, [])
    Keyword.get(opts, key, Keyword.get(app_config, key, default))
  end
end
