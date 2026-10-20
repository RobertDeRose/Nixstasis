defmodule NixstasisWeb.CurrentPath do
  @moduledoc """
  Assigns `:current_path` from the request URI on every `handle_params`, so the
  app layout can mark the current page in the sidebar and mobile navigation.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @doc """
  Attaches a `handle_params` hook that keeps `:current_path` up to date across
  live navigation.
  """
  def on_mount(:default, _params, _session, socket) do
    {:cont, attach_hook(socket, :current_path, :handle_params, &assign_current_path/3)}
  end

  # Stores the path of the URI LiveView is handling, without query or fragment.
  defp assign_current_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path)}
  end
end
