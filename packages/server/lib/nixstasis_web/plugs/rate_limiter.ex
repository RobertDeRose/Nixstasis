defmodule NixstasisWeb.Plugs.RateLimiter do
  @moduledoc """
  Per-device heartbeat rate limiter.
  """

  import Plug.Conn

  @default_limit 30
  @default_window_ms 60_000

  def init(opts), do: opts

  def call(conn, opts) do
    if heartbeat_request?(conn) do
      device_id = heartbeat_device_id(conn)
      limit = rate_limit(opts, :limit, @default_limit)
      window_ms = rate_limit(opts, :window_ms, @default_window_ms)

      case NixstasisWeb.RateLimiterStore.check_rate({:heartbeat, device_id}, limit, window_ms) do
        :ok ->
          conn

        :limited ->
          conn
          |> put_status(:too_many_requests)
          |> Phoenix.Controller.json(%{error: %{code: "rate_limited", message: "Heartbeat rate limit exceeded"}})
          |> halt()
      end
    else
      conn
    end
  end

  defp heartbeat_request?(%{method: "POST", path_info: ["api", "v1", "devices", _id, "heartbeat"]}), do: true
  defp heartbeat_request?(_conn), do: false

  defp heartbeat_device_id(%{path_params: %{"device_id" => device_id}}), do: device_id
  defp heartbeat_device_id(%{path_info: ["api", "v1", "devices", device_id, "heartbeat"]}), do: device_id

  defp rate_limit(opts, key, default) do
    app_config = Application.get_env(:nixstasis, :heartbeat_rate_limit, [])
    Keyword.get(opts, key, Keyword.get(app_config, key, default))
  end
end
