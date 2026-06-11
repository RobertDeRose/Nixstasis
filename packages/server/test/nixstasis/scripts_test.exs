defmodule Nixstasis.ScriptsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Domain
  alias Nixstasis.Devices
  alias Nixstasis.Scripts

  setup do
    {:ok, device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EE:F1",
        product_name: "script-target"
      })

    {:ok, device} = Devices.approve_device(device)
    {:ok, device} = Devices.set_remote_access(device, false)

    {:ok, draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "example",
        front_matter: %{"name" => "example", "schema" => %{"type" => "object"}},
        body: "def main():\n    return {\"value\": \"ok\"}\n"
      })

    {:ok, version} =
      Domain.create_script_version(%{
        script_draft_id: draft.id,
        version: "1",
        status: :candidate,
        front_matter: draft.front_matter,
        body: draft.body,
        rendered_content: Scripts.render_draft(draft)
      })

    %{device: device, draft: draft, version: version}
  end

  test "create_draft requires manage access", %{draft: draft} do
    assert {:error, :unauthorized} =
             Scripts.create_draft(%{"script_permissions" => %{"can_manage" => false}}, %{
               name: "x",
               front_matter: draft.front_matter,
               body: draft.body
             })
  end

  test "queue_test_run creates queued client actions and command payloads", %{
    device: device,
    draft: draft,
    version: version
  } do
    assert {:ok, run} =
             Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert run.status == :running
    assert run.target_device_ids == [device.id]

    {:ok, [action]} = Domain.list_script_client_actions()
    assert action.script_test_run_id == run.id
    assert action.kind == :test
    assert action.status == :queued
    assert action.device_id == device.id
  end

  test "ingest_test_results records client actions and finalizes the test run", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, completed} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "OK", "output" => %{"value" => "ok"}}
             ])

    assert completed.status == :passed
    assert completed.completed_at
  end

  test "validate_draft succeeds for valid script", %{draft: draft} do
    assert {:ok, run} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)

    assert run.status == :passed
    assert run.validated_at
  end

  test "validate_draft returns error when front matter is invalid" do
    {:ok, bad_draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "bad",
        front_matter: %{"name" => "bad", "schema" => %{"type" => "string"}},
        body: "def main():\n    return {}\n"
      })

    assert {:error, reason} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, bad_draft)

    assert reason =~ "schema"
  end

  test "validate_draft requires manage access", %{draft: draft} do
    assert {:error, :unauthorized} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => false}}, draft)
  end

  test "archive_draft transitions draft to archived status", %{draft: draft} do
    assert {:ok, archived} =
             Scripts.archive_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)

    assert archived.status == :archived
  end

  test "archive_draft requires manage access", %{draft: draft} do
    assert {:error, :unauthorized} =
             Scripts.archive_draft(%{"script_permissions" => %{"can_manage" => false}}, draft)
  end

  test "ingest_test_results marks run failed when any client fails", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, completed} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "ERROR"}
             ])

    assert completed.status == :failed
  end

  test "ingest_deployment_results marks run partial when any client fails", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, run} =
      Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, completed} =
             Scripts.ingest_deployment_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "ERROR"}
             ])

    assert completed.status == :partial
  end

  test "queue_deployment requires manage access", %{draft: draft, version: version, device: device} do
    assert {:error, :unauthorized} =
             Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => false}}, draft, version, [device])
  end
end
