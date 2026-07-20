defmodule Nixstasis.CommandAllowlists.Audit do
  @moduledoc """
  Emits command-policy audit events for UI/activity consumers.
  """

  require Logger

  @topic "command_policy_audit"

  def subscribe, do: Phoenix.PubSub.subscribe(Nixstasis.PubSub, @topic)

  def emit(action, attrs) when is_atom(action) and is_map(attrs) do
    payload = Map.put(attrs, :action, action)
    Logger.info("command policy audit", payload: payload)
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, @topic, {:command_policy_audit, payload})
    :ok
  end
end
