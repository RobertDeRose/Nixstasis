defmodule NixstasisWeb.PageController do
  use NixstasisWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
