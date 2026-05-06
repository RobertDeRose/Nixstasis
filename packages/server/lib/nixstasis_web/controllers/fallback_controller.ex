defmodule NixstasisWeb.FallbackController do
  use NixstasisWeb, :controller

  # This clause handles errors returned by Ash actions.
  def call(conn, {:error, %Ash.Error.Invalid{} = error}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: NixstasisWeb.ErrorJSON)
    |> render("error.json", error: error)
  end

  def call(conn, {:error, %Ash.Error.Forbidden{}}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: NixstasisWeb.ErrorJSON)
    |> render("403.json")
  end

  def call(conn, {:error, %Ash.Error.Unknown{} = error}) do
    conn
    |> put_status(:internal_server_error)
    |> put_view(json: NixstasisWeb.ErrorJSON)
    |> render("error.json", error: error)
  end

  # This clause is an example of how to handle resources that cannot be found.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: NixstasisWeb.ErrorJSON)
    |> render("404.json")
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: NixstasisWeb.ErrorJSON)
    |> render("403.json")
  end
end
