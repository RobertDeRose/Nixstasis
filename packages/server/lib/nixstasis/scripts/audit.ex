defmodule Nixstasis.Scripts.Audit do
  @moduledoc """
  Emits script-workbench audit events for downstream consumers.

  Events are logged and broadcast through PubSub. Durable retention belongs to
  the deployment logging pipeline; this module does not create an audit table.
  """

  require Logger

  @topic "script_audit"

  def subscribe, do: Phoenix.PubSub.subscribe(Nixstasis.PubSub, @topic)

  def emit(action, actor_id, attrs) when is_atom(action) and is_map(attrs) do
    emit_event(action, :operator, actor_id, attrs)
  end

  def emit(action, actor_id, attrs) when is_binary(action) and is_map(attrs) do
    emit_event(action, :operator, actor_id, attrs)
  end

  def emit_device(action, device_id, attrs) when is_atom(action) and is_map(attrs) do
    emit_event(action, :device, device_id, attrs)
  end

  def emit_device(action, device_id, attrs) when is_binary(action) and is_map(attrs) do
    emit_event(action, :device, device_id, attrs)
  end

  defp emit_event(action, actor_type, actor_id, attrs) when is_binary(actor_id) do
    if String.trim(actor_id) == "" do
      {:error, :missing_actor}
    else
      payload =
        attrs
        |> Map.put(:action, action)
        |> Map.put(:actor_id, actor_id)
        |> Map.put(:actor_type, actor_type)
        |> Map.put(:timestamp, DateTime.utc_now())

      Logger.info("script audit", payload: payload)
      Phoenix.PubSub.broadcast(Nixstasis.PubSub, @topic, {:script_audit, payload})
      :ok
    end
  end

  defp emit_event(_action, _actor_type, _actor_id, _attrs), do: {:error, :missing_actor}
end
