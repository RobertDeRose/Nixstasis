defmodule Nixstasis.Scripts do
  @moduledoc """
  Script workbench context.
  """

  alias Nixstasis.Domain
  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Scripts.Audit
  alias Nixstasis.Scripts.Authorization
  alias Nixstasis.Scripts.ScriptDeploymentRun
  alias Nixstasis.Scripts.ScriptDraft
  alias Nixstasis.Scripts.ScriptTestRun
  alias Nixstasis.Scripts.ScriptVersion

  def list_drafts, do: Domain.list_script_drafts()

  def create_draft(session, attrs) do
    with true <- Authorization.can_create?(session) do
      result = Domain.create_script_draft(attrs)
      audit_result(result, :draft_created, attrs)
      result
    else
      _ -> {:error, :unauthorized}
    end
  end

  def update_draft(session, %ScriptDraft{} = draft, attrs) do
    with true <- Authorization.can_edit?(session) do
      result = Domain.update_script_draft(draft, attrs)
      audit_result(result, :draft_updated, Map.merge(%{draft_id: draft.id}, attrs))
      result
    else
      _ -> {:error, :unauthorized}
    end
  end

  def render_draft(%ScriptDraft{front_matter: front_matter, body: body}),
    do: Nixstasis.Scripts.Validator.render_stary(front_matter, body)

  def validate_draft(session, %ScriptDraft{} = draft) do
    with true <- Authorization.can_validate?(session),
         rendered <- render_draft(draft),
         {:ok, payload} <- Nixstasis.Scripts.Validator.validate_content(rendered) do
      result =
        Domain.create_script_validation_run(%{
          script_draft_id: draft.id,
          status: :passed,
          validated_at: DateTime.utc_now(),
          front_matter: payload.front_matter,
          rendered_content: payload.rendered_content,
          details: %{}
        })

      audit_result(result, :validation_passed, %{script_draft_id: draft.id})
      result
    else
      false -> {:error, :unauthorized}
      {:error, reason} ->
        Audit.emit(:validation_failed, %{script_draft_id: draft.id, reason: reason})
        {:error, reason}
    end
  end

  def queue_test_run(session, %ScriptDraft{} = draft, %ScriptVersion{} = version, devices)
      when is_list(devices) do
    with true <- Authorization.can_test?(session) do
      device_ids = Enum.map(devices, &device_id/1)
      rendered = render_draft(draft)
      {:ok, test_run} =
        Domain.create_script_test_run(%{
          script_draft_id: draft.id,
          script_version_id: version.id,
          status: :running,
          started_at: DateTime.utc_now(),
          target_device_ids: device_ids,
          command_payload: %{type: "run_script", payload: %{content_type: "text/x-stary", data: rendered}},
          notes: %{}
        })

      Enum.each(devices, fn device ->
        Devices.queue_command(device, %{
          "type" => "run_script",
          "payload_ref" => test_run.id,
          "payload" => %{
            "content_type" => "text/x-stary",
            "name" => draft.name,
            "data" => rendered
          }
        })

        Domain.create_script_client_action(%{
          device_id: device.id,
          script_test_run_id: test_run.id,
          kind: :test,
          status: :queued,
          payload: %{"content_type" => "text/x-stary", "name" => draft.name, "data" => rendered}
        })
      end)

      Audit.emit(:test_queued, %{script_draft_id: draft.id, script_version_id: version.id, target_device_ids: device_ids})
      {:ok, test_run}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def ingest_test_results(session, %ScriptTestRun{} = test_run, results) when is_list(results) do
    with true <- Authorization.can_test?(session) do
      client_statuses =
        Enum.map(results, fn result ->
          device_id = Map.get(result, "device_id") || Map.get(result, :device_id)
          status = result_status(result)

          attrs = %{
            device_id: device_id,
            script_test_run_id: test_run.id,
            kind: :test,
            status: status,
            command_ref: Map.get(result, "command_id") || Map.get(result, :command_id),
            result_payload: result,
            acknowledged_at: DateTime.utc_now()
          }

          Domain.create_script_client_action(attrs)
          Audit.emit(:test_client_result, %{script_test_run_id: test_run.id, device_id: device_id, status: status})
          status
        end)

      final_status = if Enum.all?(client_statuses, &(&1 == :acknowledged)), do: :passed, else: :failed
      result = Domain.update_script_test_run(test_run, %{status: final_status, completed_at: DateTime.utc_now()})
      Audit.emit(:test_completed, %{script_test_run_id: test_run.id, status: final_status})
      result
    else
      _ -> {:error, :unauthorized}
    end
  end

  def queue_deployment(session, %ScriptDraft{} = draft, %ScriptVersion{} = version, devices)
      when is_list(devices) do
    with true <- Authorization.can_deploy?(session) do
      device_ids = Enum.map(devices, &device_id/1)
      rendered = render_draft(draft)
      {:ok, deployment_run} =
        Domain.create_script_deployment_run(%{
          script_draft_id: draft.id,
          script_version_id: version.id,
          status: :running,
          started_at: DateTime.utc_now(),
          target_device_ids: device_ids,
          command_payload: %{type: "install_script", payload: %{content_type: "text/x-stary", data: rendered}},
          notes: %{}
        })

      Enum.each(devices, fn device ->
        Devices.queue_command(device, %{
          "type" => "install_script",
          "payload_ref" => deployment_run.id,
          "payload" => %{
            "content_type" => "text/x-stary",
            "name" => draft.name,
            "data" => rendered
          }
        })
      end)

      Audit.emit(:deployment_queued, %{script_draft_id: draft.id, script_version_id: version.id, target_device_ids: device_ids})
      {:ok, deployment_run}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def ingest_deployment_results(session, %ScriptDeploymentRun{} = run, results) when is_list(results) do
    with true <- Authorization.can_deploy?(session) do
      client_statuses =
        Enum.map(results, fn result ->
          device_id = Map.get(result, "device_id") || Map.get(result, :device_id)
          status = result_status(result)

          Domain.create_script_client_action(%{
            device_id: device_id,
            script_deployment_run_id: run.id,
            kind: :deploy,
            status: status,
            command_ref: Map.get(result, "command_id") || Map.get(result, :command_id),
            result_payload: result,
            acknowledged_at: DateTime.utc_now()
          })

          Audit.emit(:deployment_client_result, %{script_deployment_run_id: run.id, device_id: device_id, status: status})
          status
        end)

      final_status = if Enum.all?(client_statuses, &(&1 == :acknowledged)), do: :deployed, else: :partial
      result = Domain.update_script_deployment_run(run, %{status: final_status, completed_at: DateTime.utc_now()})
      Audit.emit(:deployment_completed, %{script_deployment_run_id: run.id, status: final_status})
      result
    else
      _ -> {:error, :unauthorized}
    end
  end

  def archive_draft(session, %ScriptDraft{} = draft) do
    with true <- Authorization.can_archive?(session) do
      result = Domain.update_script_draft(draft, %{status: :archived})
      audit_result(result, :draft_archived, %{draft_id: draft.id})
      result
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp device_id(%Device{id: id}), do: id
  defp device_id(%{id: id}), do: id
  defp device_id(id) when is_binary(id), do: id

  defp result_status(result) do
    case Map.get(result, "status") || Map.get(result, :status) do
      "OK" -> :acknowledged
      :OK -> :acknowledged
      _ -> :failed
    end
  end

  defp audit_result({:ok, value}, action, attrs) do
    Audit.emit(action, Map.put(attrs, :resource_id, Map.get(value, :id)))
  end

  defp audit_result(_, _action, _attrs), do: :ok
end
