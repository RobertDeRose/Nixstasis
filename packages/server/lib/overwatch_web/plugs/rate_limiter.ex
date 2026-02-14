defmodule NixstasisWeb.Plugs.RateLimiter do
  @moduledoc """
  Placeholder rate limiter plug for API requests.
  """

  # import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # Rate limiting is currently enforced by upstream infrastructure.
    # This plug remains a no-op placeholder for future extension.
    conn
  end
end
