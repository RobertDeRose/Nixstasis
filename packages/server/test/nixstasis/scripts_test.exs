defmodule Nixstasis.ScriptsTest do
  use Nixstasis.DataCase

  alias Nixstasis.Devices
  alias Nixstasis.Domain
  alias Nixstasis.Monitoring
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
        front_matter: %{"name" => "example", "schema" => %{"type" => "object"}, "version" => "1"},
        body: "def main():\n    return {\"value\": \"ok\"}\n"
      })

    {:ok, version} =
      Domain.create_script_version(%{
        script_draft_id: draft.id,
        version: "1",
        status: :validated,
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

    {:ok, actions} = Domain.list_script_client_actions()
    action = Enum.find(actions, &(&1.script_test_run_id == run.id))
    assert action
    assert action.kind == :test
    assert action.status == :queued
    assert action.device_id == device.id

    [command] = Devices.pop_pending_commands(device)
    assert command.command_payload["defer_payload"] == false
  end

  test "queue_test_run defers large payloads while preserving fetchable content", %{
    device: device,
    draft: draft,
    version: version
  } do
    large_content = String.duplicate("x", 5_000)
    {:ok, version} = Domain.update_script_version(version, %{rendered_content: large_content})

    assert {:ok, run} =
             Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    [command] = Devices.pop_pending_commands(device)
    assert command.command_payload["defer_payload"] == true
    assert command.command_payload["payload_ref"] == run.id

    response = Monitoring.heartbeat_response_data(device, [command])
    [heartbeat_command] = response.commands
    refute Map.has_key?(heartbeat_command, :payload)
    assert heartbeat_command.payload_ref == run.id

    assert {:ok, payload} = Devices.get_command_payload(device, run.id)
    assert payload["content_type"] == "text/x-stary"
    assert payload["data"] == large_content
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

  test "validate_draft succeeds for valid script" do
    {:ok, draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "valid-versioned",
        front_matter: %{"name" => "valid-versioned", "schema" => %{"type" => "object"}, "version" => "2"},
        body: "def main():\n    return {\"value\": \"ok\"}\n"
      })

    assert {:ok, run} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)

    assert run.status == :passed
    assert run.validated_at

    {:ok, versions} = Domain.list_script_versions()
    version = Enum.find(versions, &(&1.script_draft_id == draft.id and &1.version == "2"))
    assert version.status == :validated
  end

  test "validate_draft requires front matter version and records a failed run" do
    {:ok, draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "missing-version",
        front_matter: %{"name" => "missing-version", "schema" => %{"type" => "object"}},
        body: "def main():\n    return {}\n"
      })

    assert {:error, "front matter version is required"} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)

    {:ok, runs} = Domain.list_script_validation_runs()
    run = Enum.find(runs, &(&1.script_draft_id == draft.id))
    assert run.status == :failed
    assert run.error_message == "front matter version is required"
    assert is_nil(run.script_version_id)
  end

  test "validate_draft reuses an immutable version and links each validation run" do
    {:ok, draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "repeatable-validation",
        front_matter: %{
          "name" => "repeatable-validation",
          "schema" => %{"type" => "object"},
          "version" => "1"
        },
        body: "def main():\n    return {\"value\": \"ok\"}\n"
      })

    assert {:ok, first_run} = Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)
    assert {:ok, second_run} = Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)

    {:ok, versions} = Domain.list_script_versions()
    versions = Enum.filter(versions, &(&1.script_draft_id == draft.id))
    assert [%{id: version_id, rendered_content: rendered_content}] = versions
    assert first_run.script_version_id == version_id
    assert second_run.script_version_id == version_id
    assert first_run.rendered_content == rendered_content
    assert second_run.rendered_content == rendered_content
  end

  test "validate_draft rejects changed content for an existing version and records failure" do
    {:ok, draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "immutable-version",
        front_matter: %{
          "name" => "immutable-version",
          "schema" => %{"type" => "object"},
          "version" => "1"
        },
        body: "def main():\n    return {\"value\": \"original\"}\n"
      })

    assert {:ok, _run} = Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, draft)

    {:ok, changed_draft} =
      Scripts.update_draft(%{"script_permissions" => %{"can_manage" => true}}, draft, %{
        body: "def main():\n    return {\"value\": \"changed\"}\n"
      })

    assert {:error, reason} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, changed_draft)

    assert reason == "version 1 already exists with different content"

    {:ok, versions} = Domain.list_script_versions()
    assert Enum.count(versions, &(&1.script_draft_id == draft.id)) == 1

    {:ok, runs} = Domain.list_script_validation_runs()

    failed_run =
      runs
      |> Enum.filter(&(&1.script_draft_id == draft.id))
      |> Enum.find(&(&1.status == :failed))

    assert failed_run.error_message == reason
    assert is_nil(failed_run.script_version_id)
  end

  test "queue_test_run uses validated version content", %{device: device, draft: draft, version: version} do
    {:ok, draft} =
      Scripts.update_draft(%{"script_permissions" => %{"can_manage" => true}}, draft, %{
        body: "def main():\n    return {\"value\": \"changed\"}\n"
      })

    assert {:ok, run} =
             Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert run.command_payload["payload"]["data"] == version.rendered_content
    refute run.command_payload["payload"]["data"] =~ "changed"
  end

  test "validate_draft rejects invalid starlark syntax" do
    {:ok, bad_draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "bad-syntax",
        front_matter: %{"name" => "bad-syntax", "schema" => %{"type" => "object"}, "version" => "1"},
        body: "def main():\n    if :\n        return {}\n"
      })

    assert {:error, reason} =
             Scripts.validate_draft(%{"script_permissions" => %{"can_manage" => true}}, bad_draft)

    assert reason =~ "Starlark"
  end

  test "validate_draft returns error when front matter is invalid" do
    {:ok, bad_draft} =
      Scripts.create_draft(%{"script_permissions" => %{"can_manage" => true}}, %{
        name: "bad",
        front_matter: %{"name" => "bad", "schema" => %{"type" => "string"}, "version" => "1"},
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

  test "ingest_deployment_results marks run failed when every client fails", %{
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

    assert completed.status == :failed
  end

  test "cancel_test_run marks running run failed", %{device: device, draft: draft, version: version} do
    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, cancelled} = Scripts.cancel_test_run(%{"script_permissions" => %{"can_manage" => true}}, run)
    assert cancelled.status == :failed
    assert cancelled.completed_at
  end

  test "cancel_deployment_run marks running run failed", %{device: device, draft: draft, version: version} do
    {:ok, run} =
      Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, cancelled} = Scripts.cancel_deployment_run(%{"script_permissions" => %{"can_manage" => true}}, run)
    assert cancelled.status == :failed
    assert cancelled.completed_at
  end

  test "late test results do not revive canceled test run", %{device: device, draft: draft, version: version} do
    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, _cancelled} = Scripts.cancel_test_run(%{"script_permissions" => %{"can_manage" => true}}, run)

    assert {:ok, final} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-late", "status" => "OK"}
             ])

    assert final.status == :failed
  end

  test "stale run cannot be canceled after completion", %{device: device, draft: draft, version: version} do
    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, passed} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-pass", "status" => "OK"}
             ])

    assert passed.status == :passed
    assert {:error, :not_running} = Scripts.cancel_test_run(%{"script_permissions" => %{"can_manage" => true}}, run)
  end

  test "stale deployment run cannot be canceled after completion", %{device: device, draft: draft, version: version} do
    {:ok, run} =
      Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, deployed} =
             Scripts.ingest_deployment_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-ok", "status" => "OK"}
             ])

    assert deployed.status == :deployed

    assert {:error, :not_running} =
             Scripts.cancel_deployment_run(%{"script_permissions" => %{"can_manage" => true}}, run)
  end

  test "queue_deployment requires manage access", %{draft: draft, version: version, device: device} do
    assert {:error, :unauthorized} =
             Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => false}}, draft, version, [device])
  end

  test "queue_test_run rejects unvalidated versions", %{draft: draft, device: device} do
    version = create_candidate_version!(draft)

    assert {:error, :unvalidated_version} =
             Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])
  end

  test "queue_deployment rejects unvalidated versions", %{draft: draft, device: device} do
    version = create_candidate_version!(draft)

    assert {:error, :unvalidated_version} =
             Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])
  end

  test "queue_test_run with multiple devices creates actions for each", %{
    draft: draft,
    version: version
  } do
    {:ok, device2} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:F2", product_name: "target-2"})

    {:ok, device2} = Devices.approve_device(device2)

    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [
        device_for_action(),
        device2
      ])

    assert length(run.target_device_ids) == 2
  end

  test "ingest_test_results with mixed client statuses marks run failed", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, device2} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:F3", product_name: "target-3"})

    {:ok, device2} = Devices.approve_device(device2)

    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [
        device,
        device2
      ])

    assert {:ok, completed} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "OK"},
               %{"device_id" => device2.id, "command_id" => "cmd-2", "status" => "ERROR"}
             ])

    assert completed.status == :failed
  end

  test "ingest_test_results waits when one target failed and another is pending", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, device2} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:F7", product_name: "target-7"})

    {:ok, device2} = Devices.approve_device(device2)

    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device, device2])

    assert {:ok, updated} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "ERROR"}
             ])

    assert updated.status == :running
    refute updated.completed_at
  end

  test "ingest_test_results waits for all target devices", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, version} = Domain.update_script_version(version, %{status: :validated})

    {:ok, device2} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:F6", product_name: "target-6"})

    {:ok, device2} = Devices.approve_device(device2)

    {:ok, run} =
      Scripts.queue_test_run(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device, device2])

    assert {:ok, updated} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "OK"}
             ])

    assert updated.status == :running
    refute updated.completed_at

    assert {:ok, completed} =
             Scripts.ingest_test_results(%{"script_permissions" => %{"can_manage" => true}}, updated, [
               %{"device_id" => device2.id, "command_id" => "cmd-2", "status" => "OK"}
             ])

    assert completed.status == :passed
    assert completed.completed_at
  end

  test "ingest_deployment_results marks all-failed deployment failed", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, version} = Domain.update_script_version(version, %{status: :validated})

    {:ok, run} =
      Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [device])

    assert {:ok, completed} =
             Scripts.ingest_deployment_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "ERROR"}
             ])

    assert completed.status == :failed
  end

  test "ingest_deployment_results with all successful clients marks run deployed", %{
    device: device,
    draft: draft,
    version: version
  } do
    {:ok, version} = Domain.update_script_version(version, %{status: :validated})

    {:ok, device2} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:F4", product_name: "target-4"})

    {:ok, device2} = Devices.approve_device(device2)

    {:ok, run} =
      Scripts.queue_deployment(%{"script_permissions" => %{"can_manage" => true}}, draft, version, [
        device,
        device2
      ])

    assert {:ok, completed} =
             Scripts.ingest_deployment_results(%{"script_permissions" => %{"can_manage" => true}}, run, [
               %{"device_id" => device.id, "command_id" => "cmd-1", "status" => "OK"},
               %{"device_id" => device2.id, "command_id" => "cmd-2", "status" => "OK"}
             ])

    assert completed.status == :deployed
  end

  test "update_draft modifies draft attributes", %{draft: draft} do
    assert {:ok, updated} =
             Scripts.update_draft(%{"script_permissions" => %{"can_manage" => true}}, draft, %{
               body: "def main():\n    return {\"updated\": true}\n"
             })

    assert updated.body =~ "updated"
  end

  test "update_draft requires manage access", %{draft: draft} do
    assert {:error, :unauthorized} =
             Scripts.update_draft(%{"script_permissions" => %{"can_manage" => false}}, draft, %{body: "x"})
  end

  test "list_drafts returns all drafts" do
    assert {:ok, drafts} = Scripts.list_drafts()
    assert is_list(drafts)
    assert drafts != []
  end

  defp create_candidate_version!(draft) do
    {:ok, version} =
      Domain.create_script_version(%{
        script_draft_id: draft.id,
        version: "candidate",
        status: :candidate,
        front_matter: draft.front_matter,
        body: draft.body,
        rendered_content: Scripts.render_draft(draft)
      })

    version
  end

  defp device_for_action do
    {:ok, device} =
      Devices.register_device(%{mac_address: "AA:BB:CC:DD:EE:F5", product_name: "target-5"})

    {:ok, device} = Devices.approve_device(device)
    device
  end
end
