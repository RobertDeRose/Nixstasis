defmodule Nixstasis.Scripts.Authorization do
  @moduledoc """
  Authorization helpers for script workbench actions.
  """

  alias NixstasisWeb.Permissions

  def actor_id(session), do: Permissions.actor_id(session)

  def can_view?(session), do: Permissions.can_view_scripts?(session)
  def can_manage?(session), do: Permissions.can_manage_scripts?(session)

  def can_create?(session), do: can_manage?(session)
  def can_edit?(session), do: can_manage?(session)
  def can_validate?(session), do: can_manage?(session)
  def can_test?(session), do: can_manage?(session)
  def can_deploy?(session), do: can_manage?(session)
  def can_archive?(session), do: can_manage?(session)

  @doc "Returns whether every non-empty target list is inside the trusted device scope."
  def can_target_devices?(session, target_device_ids) when is_map(session) and is_list(target_device_ids) do
    target_device_ids != [] and Enum.all?(target_device_ids, &valid_device_id?/1) and
      case Permissions.authorized_device_ids(Permissions.device_permissions(session)) do
        nil ->
          true

        authorized_device_ids ->
          Enum.all?(target_device_ids, fn device_id ->
            MapSet.member?(authorized_device_ids, device_id) or
              MapSet.member?(authorized_device_ids, to_string(device_id)) or
              uuid_string_member?(authorized_device_ids, device_id)
          end)
      end
  end

  def can_target_devices?(_session, _target_device_ids), do: false

  defp valid_device_id?(device_id) do
    is_binary(device_id) and match?({:ok, _}, Ecto.UUID.cast(device_id))
  end

  defp uuid_string_member?(authorized_device_ids, device_id) when is_binary(device_id) do
    case Ecto.UUID.cast(device_id) do
      {:ok, cast_id} -> MapSet.member?(authorized_device_ids, cast_id)
      :error -> false
    end
  end

  defp uuid_string_member?(_authorized_device_ids, _device_id), do: false
end
