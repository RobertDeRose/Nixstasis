defmodule Nixstasis.Devices.GroupAudit do
  @moduledoc """
  Emits structured device group audit events after committed context operations.
  """

  require Logger

  @topic "device_group_audit"

  def subscribe, do: Phoenix.PubSub.subscribe(Nixstasis.PubSub, @topic)

  def emit(action, actor_id, group_id, device_ids)
      when is_atom(action) and is_binary(actor_id) and is_binary(group_id) and is_list(device_ids) do
    payload = %{
      action: action,
      actor_id: actor_id,
      timestamp: DateTime.utc_now(),
      group_id: group_id,
      device_ids: device_ids
    }

    Logger.info("device group audit", payload: payload)
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, @topic, {:device_group_audit, payload})
    :ok
  end
end
