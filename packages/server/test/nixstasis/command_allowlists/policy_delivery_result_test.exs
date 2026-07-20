defmodule Nixstasis.CommandAllowlists.PolicyDeliveryResultTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  setup do
    {:ok, device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EF:02",
        product_name: "policy-delivery-target"
      })

    {:ok, device} = Devices.approve_device(device)

    {:ok, assignment} =
      Domain.create_command_policy_assignment(%{
        device_id: device.id,
        revision: 1,
        version: "policy-1",
        resolved_policy: %{"commands" => %{"df" => "/usr/bin/df"}}
      })

    {:ok, pending_command} =
      Domain.create_pending_command(%{
        device_id: device.id,
        command_payload: %{
          "type" => "apply_command_policy",
          "assignment_id" => assignment.id,
          "revision" => 1
        }
      })

    %{assignment: assignment, pending_command: pending_command}
  end

  test "delivery results persist client acknowledgement payloads", context do
    assert {:ok, result} =
             Domain.create_command_policy_delivery_result(%{
               assignment_id: context.assignment.id,
               pending_command_id: context.pending_command.id,
               status: :acknowledged,
               command_ref: "apply_command_policy",
               client_payload: %{"revision" => 1}
             })

    assert result.assignment_id == context.assignment.id
    assert result.pending_command_id == context.pending_command.id
    assert result.status == :acknowledged
    assert result.client_payload["revision"] == 1
  end

  test "delivery results capture failure reasons without mutating assignment", context do
    assert {:ok, result} =
             Domain.create_command_policy_delivery_result(%{
               assignment_id: context.assignment.id,
               status: :unsupported,
               command_ref: "apply_command_policy",
               failure_reason: "unsupported command type"
             })

    assert result.status == :unsupported
    assert result.failure_reason == "unsupported command type"
  end
end
