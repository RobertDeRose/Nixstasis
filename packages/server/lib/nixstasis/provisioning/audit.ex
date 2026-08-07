defmodule Nixstasis.Provisioning.Audit do
  @moduledoc """
  Emits structured audit events for AtomixOS bootstrap delivery.
  """

  require Logger

  @topic "provisioning_audit"

  def emit(action, actor_id, attrs) when is_atom(action) and is_binary(actor_id) and is_map(attrs) do
    payload = Map.merge(%{action: action, actor_id: actor_id, occurred_at: DateTime.utc_now()}, attrs)
    Logger.info("provisioning audit", payload: payload)
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, @topic, {:provisioning_audit, payload})
    :ok
  end

  def emit(_action, _actor_id, _attrs), do: :ok
end
