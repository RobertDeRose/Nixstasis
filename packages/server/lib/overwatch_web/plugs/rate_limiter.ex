defmodule NixstasisWeb.Plugs.RateLimiter do
  # import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # TODO: Implement rate limiting using Hammer or similar.
    # We would extract device ID/Token here and check limits.
    conn
  end
end
