defmodule Nixstasis.CommandAllowlists.DevicePolicyAssignmentTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  setup do
    {:ok, device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EF:01",
        product_name: "policy-target"
      })

    {:ok, device} = Devices.approve_device(device)
    %{device: device}
  end

  test "device policy assignments persist resolved snapshots and revisions", %{device: device} do
    assert {:ok, assignment} =
             Domain.create_command_policy_assignment(%{
               device_id: device.id,
               status: :queued,
               revision: 1,
               version: "policy-1",
               resolved_policy: %{"commands" => %{"df" => "/usr/bin/df"}},
               source_snapshot: %{"entries" => []},
               queued_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })

    assert assignment.device_id == device.id
    assert assignment.status == :queued
    assert assignment.revision == 1
    assert assignment.resolved_policy["commands"]["df"] == "/usr/bin/df"

    refute function_exported?(Domain, :update_command_policy_assignment, 2)
    refute assignment.drift_warning
  end

  test "assignment sources pin selected source versions", %{device: device} do
    assert {:ok, entry} =
             Domain.create_command_allowlist_entry(%{
               name: "df",
               command_path: "/usr/bin/df"
             })

    assert {:ok, assignment} =
             Domain.create_command_policy_assignment(%{
               device_id: device.id,
               revision: 2,
               version: "policy-2",
               resolved_policy: %{"commands" => %{"df" => "/usr/bin/df"}}
             })

    assert {:ok, source} =
             Domain.create_command_policy_assignment_source(%{
               assignment_id: assignment.id,
               source_kind: "command_entry",
               source_id: entry.id,
               source_version: entry.current_version,
               source_snapshot: %{"name" => entry.name, "command_path" => entry.command_path}
             })

    assert source.assignment_id == assignment.id
    assert source.source_id == entry.id
    assert source.source_version == 1
  end
end
