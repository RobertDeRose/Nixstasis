defmodule NixstasisWeb.CommandPolicyController do
  use NixstasisWeb, :controller

  alias Nixstasis.Domain
  alias NixstasisWeb.Permissions

  def preview(conn, params) do
    session = get_session(conn)
    device_ids = normalize_ids(params["device_ids"] || params[:device_ids])

    cond do
      not Permissions.can_manage_command_policies?(session) ->
        conn |> put_status(:forbidden) |> json(%{error: "command policy management is not permitted"})

      device_ids == [] ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "at least one device is required"})

      true ->
        with :ok <- authorize_devices(session, device_ids),
             {:ok, preview} <- Domain.preview_command_policy(params) do
          json(conn, %{data: Map.put(preview, :affected_device_ids, device_ids)})
        else
          {:error, :unauthorized_device} ->
            conn |> put_status(:forbidden) |> json(%{error: "device is not permitted for command policy assignment"})

          {:error, reason} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
        end
    end
  end

  defp authorize_devices(session, device_ids) do
    with {:ok, devices} <- Domain.list_devices() do
      devices_by_id = Map.new(devices, &{&1.id, &1})

      if Enum.all?(device_ids, &assignable_device?(session, devices_by_id[&1])) do
        :ok
      else
        {:error, :unauthorized_device}
      end
    end
  end

  defp assignable_device?(session, device) do
    Permissions.can_assign_command_policy_to_device?(session, device)
  end

  defp normalize_ids(ids) when is_list(ids), do: Enum.filter(ids, &is_binary/1)
  defp normalize_ids(_), do: []
end
