defmodule NixstasisWeb.Plugs.DevicePermissions do
  @moduledoc """
  Populates `device_permissions` in the session for device authorization.

  When an authentication system is added, this plug should read the
  authenticated user/role and derive scoped permissions. Until then,
  all requests receive full device permissions.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_session(conn, "device_permissions") do
      permissions when is_map(permissions) ->
        conn

      _ ->
        put_session(conn, "device_permissions", default_permissions())
    end
  end

  defp default_permissions do
    %{
      "can_view" => true,
      "can_remote_access" => true
    }
  end
end
