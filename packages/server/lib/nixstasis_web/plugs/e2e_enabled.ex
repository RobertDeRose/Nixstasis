defmodule NixstasisWeb.Plugs.E2EEnabled do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:nixstasis, :e2e_enabled?, false) do
      conn
    else
      conn
      |> send_resp(:not_found, "")
      |> halt()
    end
  end
end
