defmodule Nixstasis.CommandAllowlists do
  @moduledoc """
  Command policy workflow helpers.
  """

  alias Nixstasis.CommandAllowlists.Audit
  alias Nixstasis.CommandAllowlists.DevicePolicyAssignment
  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Domain

  def ingest_command_results(%Device{} = device, results) when is_list(results) do
    Enum.each(results, &ingest_result(device, &1))
  end

  def ingest_command_results(_device, _results), do: :ok

  defp ingest_result(%Device{} = device, result) when is_map(result) do
    with {:ok, payload} <- Devices.command_payload_for_result(device, result),
         true <- apply_command_policy_payload?(payload),
         assignment_id when is_binary(assignment_id) <- payload_assignment_id(payload),
         {:ok, assignment} <- Domain.get_command_policy_assignment(assignment_id) do
      {delivery_status, failure_reason} = delivery_status(result)

      {:ok, _delivery_result} =
        Domain.create_command_policy_delivery_result(%{
          assignment_id: assignment.id,
          pending_command_id: Map.get(result, "command_id") || Map.get(result, :command_id),
          status: delivery_status,
          command_ref: "apply_command_policy",
          client_payload: result,
          failure_reason: failure_reason
        })

      update_assignment_status(assignment, delivery_status)
      Audit.emit(:assignment_delivery_result, %{assignment_id: assignment.id, status: delivery_status})
    else
      _ -> :ok
    end
  end

  defp ingest_result(_device, _result), do: :ok

  defp update_assignment_status(%DevicePolicyAssignment{} = assignment, :acknowledged) do
    Audit.emit(:assignment_acknowledged, %{assignment_id: assignment.id, device_id: assignment.device_id})

    assignment
    |> Ash.Changeset.for_update(:update, %{
      status: :acknowledged,
      acknowledged_at: DateTime.utc_now(),
      failed_at: nil
    })
    |> Ash.update(domain: Domain)
  end

  defp update_assignment_status(%DevicePolicyAssignment{} = assignment, _delivery_status) do
    Audit.emit(:assignment_failed, %{assignment_id: assignment.id, device_id: assignment.device_id})

    assignment
    |> Ash.Changeset.for_update(:update, %{
      status: :failed,
      failed_at: DateTime.utc_now()
    })
    |> Ash.update(domain: Domain)
  end

  defp apply_command_policy_payload?(payload) do
    (payload["type"] || payload[:type]) == "apply_command_policy"
  end

  defp payload_assignment_id(payload) do
    payload["payload_ref"] || payload[:payload_ref]
  end

  defp delivery_status(result) do
    case Map.get(result, "status") || Map.get(result, :status) do
      value when value in ["OK", :OK] -> {:acknowledged, nil}
      _ -> failed_delivery_status(Map.get(result, "error") || Map.get(result, :error))
    end
  end

  defp failed_delivery_status(error) when is_binary(error) do
    # ponytail: client/server currently share failure meaning by stable error substrings;
    # switch to explicit error codes when the client result contract grows.
    cond do
      String.contains?(error, "unsupported command") -> {:unsupported, error}
      String.contains?(error, "conflicts with existing policy") -> {:conflict, error}
      String.contains?(error, "stale") or String.contains?(error, "lower revision") -> {:stale, error}
      String.contains?(error, "persist") -> {:persistence_failed, error}
      true -> {:failed, error}
    end
  end

  defp failed_delivery_status(_error), do: {:failed, nil}
end
