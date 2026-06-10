defmodule Nixstasis.Scripts.Audit do
  @moduledoc """
  Emits script-workbench audit events for downstream consumers.
  """

  require Logger

  @topic "script_audit"

  def emit(action, attrs) when is_atom(action) and is_map(attrs) do
    payload = Map.put(attrs, :action, action)
    Logger.info("script audit", payload: payload)
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, @topic, {:script_audit, payload})
    :ok
  end

  def emit(action, attrs) when is_binary(action) and is_map(attrs) do
    emit(String.to_existing_atom(action), attrs)
  rescue
    ArgumentError ->
      Logger.info("script audit", payload: Map.put(attrs, :action, action))
      Phoenix.PubSub.broadcast(Nixstasis.PubSub, @topic, {:script_audit, Map.put(attrs, :action, action)})
      :ok
  end
end
