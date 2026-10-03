defmodule NixstasisWeb.Permissions do
  @moduledoc """
  Centralized permission helpers for LiveViews.

  Device functions (`can_view_device_details?/1,2`, `can_remote_access_device?/1,2`)
  accept a pre-extracted permissions map (from `device_permissions/1`).

  Report functions (`can_view_reports?/1`, `can_manage_reports?/1`) accept the raw
  session map and extract report permissions internally.
  """

  alias Nixstasis.Devices.Device
  alias Nixstasis.Devices.GroupAuthorization

  def device_permissions(session), do: permission_map(session, "device_permissions")
  def report_permissions(session), do: permission_map(session, "report_permissions")
  def script_permissions(session), do: permission_map(session, "script_permissions")
  def command_policy_permissions(session), do: permission_map(session, "command_policy_permissions")

  def can_view_device_details?(permissions, device_id \\ nil)

  def can_view_device_details?(permissions, nil) when is_map(permissions), do: permissions["can_view"] == true

  def can_view_device_details?(permissions, device_id) when is_map(permissions) do
    permissions["can_view"] == true and device_authorized?(permissions, device_id)
  end

  def can_view_device_details?(_, _), do: false

  def can_remote_access_device?(permissions, device_id \\ nil)

  def can_remote_access_device?(permissions, nil) when is_map(permissions), do: permissions["can_remote_access"] == true

  def can_remote_access_device?(permissions, device_id) when is_map(permissions) do
    permissions["can_remote_access"] == true and device_authorized?(permissions, device_id)
  end

  def can_remote_access_device?(_, _), do: false

  def can_manage_devices?(permissions) when is_map(permissions), do: permissions["can_manage"] == true
  def can_manage_devices?(_permissions), do: false

  def can_manage_all_devices?(permissions) when is_map(permissions) do
    permissions["can_manage"] == true and authorized_device_ids(permissions) == nil
  end

  def can_manage_all_devices?(_permissions), do: false

  def can_create_devices?(permissions), do: can_manage_all_devices?(permissions)

  @doc "Builds trusted authorization for device group context operations."
  def device_group_authorization(session) when is_map(session) do
    permissions = device_permissions(session)

    with {:ok, actor_id} <- group_actor_id(session),
         {:ok, authorized_device_ids} <- validate_group_device_scope(authorized_device_ids(permissions)) do
      {:ok,
       %GroupAuthorization{
         actor_id: actor_id,
         can_manage_devices?: can_manage_devices?(permissions),
         can_manage_all_devices?: can_manage_all_devices?(permissions),
         authorized_device_ids: authorized_device_ids
       }}
    end
  end

  def device_group_authorization(_session), do: {:error, :missing_actor}

  def can_manage_device?(permissions, device_id) when is_map(permissions) do
    permissions["can_manage"] == true and device_authorized?(permissions, device_id)
  end

  def can_manage_device?(_permissions, _device_id), do: false

  def authorized_device_ids(permissions) when is_map(permissions) do
    ids =
      [
        Map.get(permissions, "device_id"),
        Map.get(permissions, "device_ids"),
        Map.get(permissions, "allowed_device_ids")
      ]
      |> Enum.flat_map(&normalize_authorized_device_ids/1)
      |> Enum.uniq()

    cond do
      ids != [] -> MapSet.new(ids)
      scoped_device_permissions?(permissions) -> MapSet.new()
      true -> nil
    end
  end

  def authorized_device_ids(_permissions), do: nil

  def can_view_reports?(session) when is_map(session), do: report_permissions(session)["can_view"] == true
  def can_view_reports?(_session), do: false

  def can_manage_reports?(session) when is_map(session), do: report_permissions(session)["can_manage"] == true
  def can_manage_reports?(_session), do: false

  def can_view_scripts?(session) when is_map(session), do: script_permissions(session)["can_view"] == true
  def can_view_scripts?(_session), do: false

  def can_manage_scripts?(session) when is_map(session), do: script_permissions(session)["can_manage"] == true
  def can_manage_scripts?(_session), do: false

  @doc "Returns the trusted operator subject or email used for audit attribution."
  def actor_id(session) when is_map(session) do
    case Map.get(session, "operator_context") do
      context when is_map(context) ->
        case normalize_actor_id(context["subject"]) || normalize_actor_id(context["email"]) do
          nil -> {:error, :missing_actor}
          actor_id -> {:ok, actor_id}
        end

      _context ->
        case local_actor_id() do
          nil -> {:error, :missing_actor}
          actor_id -> {:ok, actor_id}
        end
    end
  end

  def actor_id(_session) do
    case local_actor_id() do
      nil -> {:error, :missing_actor}
      actor_id -> {:ok, actor_id}
    end
  end

  def can_view_command_policy_status?(session) when is_map(session),
    do: command_policy_permissions(session)["can_view_status"] == true

  def can_view_command_policy_status?(_session), do: false

  def can_view_command_policy_details?(session) when is_map(session),
    do: command_policy_permissions(session)["can_view_details"] == true

  def can_view_command_policy_details?(_session), do: false

  def can_manage_command_policies?(session) when is_map(session),
    do: command_policy_permissions(session)["can_manage"] == true

  def can_manage_command_policies?(_session), do: false

  def can_manage_command_policy_for_device?(session, device_id) when is_map(session) do
    can_manage_command_policies?(session) and can_manage_device?(device_permissions(session), device_id)
  end

  def can_manage_command_policy_for_device?(_session, _device_id), do: false

  def can_assign_command_policy_to_device?(session, %Device{id: id, approval_status: :approved}) do
    can_manage_command_policy_for_device?(session, id)
  end

  def can_assign_command_policy_to_device?(_session, _device), do: false

  defp validate_group_device_scope(nil), do: {:ok, nil}

  defp validate_group_device_scope(%MapSet{} = ids) do
    Enum.reduce_while(ids, {:ok, MapSet.new()}, fn id, {:ok, valid_ids} ->
      case Ecto.UUID.cast(id) do
        {:ok, valid_id} -> {:cont, {:ok, MapSet.put(valid_ids, valid_id)}}
        :error -> {:halt, {:error, :invalid_device_scope}}
      end
    end)
  end

  defp group_actor_id(session), do: actor_id(session)

  defp local_actor_id do
    if Application.get_env(:nixstasis, :local_browser_auth_fallback?, false), do: "local-development"
  end

  defp normalize_actor_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      actor_id -> actor_id
    end
  end

  defp normalize_actor_id(_value), do: nil

  defp permission_map(session, key) when is_map(session) do
    case Map.get(session, key) do
      permissions when is_map(permissions) -> permissions
      _ -> %{}
    end
  end

  defp permission_map(_session, _key), do: %{}

  defp device_authorized?(permissions, device_id) when is_binary(device_id) do
    case authorized_device_ids(permissions) do
      nil -> true
      ids -> MapSet.member?(ids, device_id)
    end
  end

  defp device_authorized?(_permissions, _device_id), do: false

  defp scoped_device_permissions?(permissions) when is_map(permissions) do
    Enum.any?(["device_id", "device_ids", "allowed_device_ids"], &Map.has_key?(permissions, &1))
  end

  defp scoped_device_permissions?(_permissions), do: false

  defp normalize_authorized_device_ids(value) when is_binary(value), do: [value]
  defp normalize_authorized_device_ids(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp normalize_authorized_device_ids(_value), do: []
end
