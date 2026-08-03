defmodule Nixstasis.Scripts do
  @moduledoc """
  Script workbench context.
  """

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Domain
  alias Nixstasis.Scripts.Audit
  alias Nixstasis.Scripts.Authorization
  alias Nixstasis.Scripts.ScriptDeploymentRun
  alias Nixstasis.Scripts.ScriptDraft
  alias Nixstasis.Scripts.ScriptTestRun
  alias Nixstasis.Scripts.ScriptVersion
  alias Nixstasis.Scripts.Validator

  @inline_script_payload_limit 4_096

  def list_drafts, do: Domain.list_script_drafts()

  def ingest_command_results(%Device{} = device, results) when is_list(results) do
    results
    |> Enum.group_by(&command_result_ref(device, &1))
    |> Enum.each(fn
      {{:test, run_id}, grouped_results} ->
        with %ScriptTestRun{} = run <- get_test_run(run_id) do
          ingest_test_results(system_session(), run, attach_device_id(device, grouped_results))
        end

      {{:deploy, run_id}, grouped_results} ->
        with %ScriptDeploymentRun{} = run <- get_deployment_run(run_id) do
          ingest_deployment_results(system_session(), run, attach_device_id(device, grouped_results))
        end

      _ ->
        :ok
    end)
  end

  def ingest_command_results(_device, _results), do: :ok

  def create_draft(session, attrs) do
    if Authorization.can_create?(session) do
      result = Domain.create_script_draft(attrs)
      audit_result(result, :draft_created, attrs)
      result
    else
      {:error, :unauthorized}
    end
  end

  def update_draft(session, %ScriptDraft{} = draft, attrs) do
    if Authorization.can_edit?(session) do
      result = Domain.update_script_draft(draft, attrs)
      audit_result(result, :draft_updated, Map.merge(%{draft_id: draft.id}, attrs))
      result
    else
      {:error, :unauthorized}
    end
  end

  def render_draft(%ScriptDraft{front_matter: front_matter, body: body}),
    do: Validator.render_stary(front_matter, body)

  def validate_draft(session, %ScriptDraft{} = draft) do
    if Authorization.can_validate?(session) do
      rendered = render_draft(draft)

      validation =
        with {:ok, version} <- draft_version(draft),
             rendered_content when is_binary(rendered_content) <- rendered,
             {:ok, payload} <- Validator.validate_content(rendered_content) do
          {:ok, version, payload}
        else
          {:error, reason} -> {:error, reason}
          _ -> {:error, "stary content could not be rendered"}
        end

      case validation do
        {:ok, version, payload} ->
          persist_validated_draft(draft, version, payload)

        {:error, reason} ->
          record_failed_validation(draft, rendered, reason)
      end
    else
      {:error, :unauthorized}
    end
  end

  defp persist_validated_draft(%ScriptDraft{} = draft, version, payload) do
    case get_or_create_script_version(draft, version, payload) do
      {:ok, script_version} ->
        with {:ok, _draft} <- Domain.update_script_draft(draft, %{status: :validated}),
             {:ok, result} <-
               Domain.create_script_validation_run(%{
                 script_draft_id: draft.id,
                 script_version_id: script_version.id,
                 status: :passed,
                 validated_at: DateTime.utc_now(),
                 front_matter: payload.front_matter,
                 rendered_content: script_version.rendered_content,
                 details: %{}
               }) do
          audit_result(result, :validation_passed, %{script_draft_id: draft.id, script_version_id: script_version.id})
          broadcast_script(draft.id)
          {:ok, result}
        end

      {:error, reason} ->
        record_failed_validation(draft, payload.rendered_content, reason)
    end
  end

  defp get_or_create_script_version(%ScriptDraft{} = draft, version, payload) do
    case find_script_version(draft.id, version) do
      {:error, reason} ->
        {:error, reason}

      nil ->
        Domain.create_script_version(%{
          script_draft_id: draft.id,
          version: version,
          status: :validated,
          front_matter: payload.front_matter,
          body: payload.body,
          rendered_content: payload.rendered_content
        })

      %ScriptVersion{rendered_content: rendered_content} = script_version
      when rendered_content == payload.rendered_content ->
        case script_version.status do
          :candidate -> Domain.update_script_version(script_version, %{status: :validated})
          _status -> {:ok, script_version}
        end

      %ScriptVersion{} ->
        {:error, "version #{version} already exists with different content"}
    end
  end

  defp find_script_version(draft_id, version) do
    case Domain.list_script_versions() do
      {:ok, versions} -> Enum.find(versions, &(&1.script_draft_id == draft_id and &1.version == version))
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_failed_validation(%ScriptDraft{} = draft, rendered, reason) do
    message = validation_error_message(reason)

    _result =
      Domain.create_script_validation_run(%{
        script_draft_id: draft.id,
        status: :failed,
        front_matter: draft.front_matter,
        rendered_content: validation_rendered_content(rendered),
        error_type: "validation",
        error_message: message,
        details: %{"reason" => message}
      })

    Audit.emit(:validation_failed, %{script_draft_id: draft.id, reason: message})
    broadcast_script(draft.id)
    {:error, reason}
  end

  defp validation_rendered_content(rendered) when is_binary(rendered), do: rendered
  defp validation_rendered_content(_rendered), do: ""

  defp validation_error_message(reason) when is_binary(reason), do: reason
  defp validation_error_message(reason), do: inspect(reason)

  def queue_test_run(session, %ScriptDraft{} = draft, %ScriptVersion{} = version, devices)
      when is_list(devices) do
    with true <- Authorization.can_test?(session),
         :ok <- require_validated_version(version) do
      device_ids = Enum.map(devices, &device_id/1)
      rendered = version.rendered_content

      {:ok, test_run} =
        Domain.create_script_test_run(%{
          script_draft_id: draft.id,
          script_version_id: version.id,
          status: :running,
          started_at: DateTime.utc_now(),
          target_device_ids: device_ids,
          command_payload: %{},
          notes: %{}
        })

      command_payload = script_command_payload("run_script", draft.name, test_run.id, rendered)
      {:ok, test_run} = Domain.update_script_test_run(test_run, %{command_payload: command_payload})

      Enum.each(devices, fn device ->
        Devices.queue_command(device, command_payload)

        Domain.create_script_client_action(%{
          device_id: device.id,
          script_test_run_id: test_run.id,
          kind: :test,
          status: :queued,
          payload_ref: test_run.id,
          payload: command_payload["payload"]
        })
      end)

      Audit.emit(:test_queued, %{
        script_draft_id: draft.id,
        script_version_id: version.id,
        target_device_ids: device_ids
      })

      broadcast_script(draft.id)
      {:ok, test_run}
    else
      {:error, :unvalidated_version} -> {:error, :unvalidated_version}
      _ -> {:error, :unauthorized}
    end
  end

  def ingest_test_results(session, %ScriptTestRun{} = test_run, results) when is_list(results) do
    with true <- Authorization.can_test?(session),
         %ScriptTestRun{status: :running} = current_run <- latest_test_run_by_id(test_run.id) do
      Enum.each(results, fn result ->
        device_id = Map.get(result, "device_id") || Map.get(result, :device_id)
        status = result_status(result)

        attrs =
          timestamp_client_result(%{
            device_id: device_id,
            script_test_run_id: test_run.id,
            kind: :test,
            status: status,
            command_ref: Map.get(result, "command_id") || Map.get(result, :command_id),
            result_payload: result,
            payload_ref: test_run.id
          })

        upsert_client_action(attrs)
        Audit.emit(:test_client_result, %{script_test_run_id: test_run.id, device_id: device_id, status: status})
      end)

      final_status = test_run_status(current_run)
      attrs = run_update_attrs(final_status)
      result = Domain.update_script_test_run(current_run, attrs)

      if final_status != :running,
        do: Audit.emit(:test_completed, %{script_test_run_id: test_run.id, status: final_status})

      broadcast_script(test_run.script_draft_id)
      result
    else
      %ScriptTestRun{} = run -> {:ok, run}
      _ -> {:error, :unauthorized}
    end
  end

  def queue_deployment(session, %ScriptDraft{} = draft, %ScriptVersion{} = version, devices)
      when is_list(devices) do
    with true <- Authorization.can_deploy?(session),
         :ok <- require_validated_version(version) do
      device_ids = Enum.map(devices, &device_id/1)
      rendered = version.rendered_content

      {:ok, deployment_run} =
        Domain.create_script_deployment_run(%{
          script_draft_id: draft.id,
          script_version_id: version.id,
          status: :running,
          started_at: DateTime.utc_now(),
          target_device_ids: device_ids,
          command_payload: %{},
          notes: %{}
        })

      command_payload = script_command_payload("install_script", draft.name, deployment_run.id, rendered)

      {:ok, deployment_run} =
        Domain.update_script_deployment_run(deployment_run, %{command_payload: command_payload})

      Enum.each(devices, fn device ->
        Devices.queue_command(device, command_payload)

        Domain.create_script_client_action(%{
          device_id: device.id,
          script_deployment_run_id: deployment_run.id,
          kind: :deploy,
          status: :queued,
          payload_ref: deployment_run.id,
          payload: command_payload["payload"]
        })
      end)

      Audit.emit(:deployment_queued, %{
        script_draft_id: draft.id,
        script_version_id: version.id,
        target_device_ids: device_ids
      })

      broadcast_script(draft.id)
      {:ok, deployment_run}
    else
      {:error, :unvalidated_version} -> {:error, :unvalidated_version}
      _ -> {:error, :unauthorized}
    end
  end

  def ingest_deployment_results(session, %ScriptDeploymentRun{} = run, results) when is_list(results) do
    with true <- Authorization.can_deploy?(session),
         %ScriptDeploymentRun{status: :running} = current_run <- latest_deployment_run_by_id(run.id) do
      Enum.each(results, fn result ->
        device_id = Map.get(result, "device_id") || Map.get(result, :device_id)
        status = result_status(result)

        attrs =
          timestamp_client_result(%{
            device_id: device_id,
            script_deployment_run_id: run.id,
            kind: :deploy,
            status: status,
            command_ref: Map.get(result, "command_id") || Map.get(result, :command_id),
            result_payload: result,
            payload_ref: run.id
          })

        upsert_client_action(attrs)

        Audit.emit(:deployment_client_result, %{
          script_deployment_run_id: run.id,
          device_id: device_id,
          status: status
        })
      end)

      final_status = deployment_run_status(current_run)
      attrs = run_update_attrs(final_status)
      result = Domain.update_script_deployment_run(current_run, attrs)

      if final_status != :running,
        do: Audit.emit(:deployment_completed, %{script_deployment_run_id: run.id, status: final_status})

      broadcast_script(run.script_draft_id)
      result
    else
      %ScriptDeploymentRun{} = run -> {:ok, run}
      _ -> {:error, :unauthorized}
    end
  end

  def cancel_test_run(session, %ScriptTestRun{} = run) do
    with true <- Authorization.can_test?(session),
         %ScriptTestRun{} = current_run <- latest_test_run_by_id(run.id),
         true <- current_run.status in [:pending, :running] do
      result = Domain.update_script_test_run(current_run, %{status: :failed, completed_at: DateTime.utc_now()})
      mark_client_actions_failed(:test, current_run.id)
      audit_result(result, :test_cancelled, %{script_test_run_id: run.id})
      broadcast_script(run.script_draft_id)
      result
    else
      false -> {:error, :not_running}
      %ScriptTestRun{} -> {:error, :not_running}
      _ -> {:error, :unauthorized}
    end
  end

  def cancel_deployment_run(session, %ScriptDeploymentRun{} = run) do
    with true <- Authorization.can_deploy?(session),
         %ScriptDeploymentRun{} = current_run <- latest_deployment_run_by_id(run.id),
         true <- current_run.status in [:pending, :running] do
      result = Domain.update_script_deployment_run(current_run, %{status: :failed, completed_at: DateTime.utc_now()})
      mark_client_actions_failed(:deploy, current_run.id)
      audit_result(result, :deployment_cancelled, %{script_deployment_run_id: run.id})
      broadcast_script(run.script_draft_id)
      result
    else
      false -> {:error, :not_running}
      %ScriptDeploymentRun{} -> {:error, :not_running}
      _ -> {:error, :unauthorized}
    end
  end

  def archive_draft(session, %ScriptDraft{} = draft) do
    if Authorization.can_archive?(session) do
      result = Domain.update_script_draft(draft, %{status: :archived})
      audit_result(result, :draft_archived, %{draft_id: draft.id})
      result
    else
      {:error, :unauthorized}
    end
  end

  defp script_command_payload(type, name, payload_ref, rendered) do
    %{
      "type" => type,
      "payload_ref" => payload_ref,
      "defer_payload" => byte_size(rendered) > @inline_script_payload_limit,
      "payload" => %{
        "content_type" => "text/x-stary",
        "name" => name,
        "data" => rendered
      }
    }
  end

  defp draft_version(%ScriptDraft{front_matter: front_matter}) do
    case Map.get(front_matter, "version") do
      version when is_binary(version) ->
        version = String.trim(version)
        if version == "", do: {:error, "front matter version is required"}, else: {:ok, version}

      _ ->
        {:error, "front matter version is required"}
    end
  end

  defp require_validated_version(%ScriptVersion{status: :validated}), do: :ok
  defp require_validated_version(_), do: {:error, :unvalidated_version}

  defp run_update_attrs(:running), do: %{status: :running, completed_at: nil}
  defp run_update_attrs(status), do: %{status: status, completed_at: DateTime.utc_now()}

  defp test_run_status(%ScriptTestRun{} = run) do
    statuses = run_statuses(:test, run.id, run.target_device_ids)

    cond do
      Enum.any?(statuses, &pending_status?/1) -> :running
      Enum.all?(statuses, &(&1 == :acknowledged)) -> :passed
      true -> :failed
    end
  end

  defp deployment_run_status(%ScriptDeploymentRun{} = run) do
    statuses = run_statuses(:deploy, run.id, run.target_device_ids)

    cond do
      Enum.any?(statuses, &pending_status?/1) -> :running
      Enum.all?(statuses, &(&1 == :acknowledged)) -> :deployed
      Enum.any?(statuses, &(&1 == :acknowledged)) -> :partial
      true -> :failed
    end
  end

  defp pending_status?(status), do: status in [:queued, :delivered]

  defp run_statuses(kind, run_id, target_device_ids) do
    actions =
      Domain.list_script_client_actions()
      |> elem(1)
      |> Enum.filter(fn action ->
        (kind == :test and action.kind == :test and action.script_test_run_id == run_id) or
          (kind == :deploy and action.kind == :deploy and action.script_deployment_run_id == run_id)
      end)
      |> Map.new(&{&1.device_id, &1.status})

    Enum.map(target_device_ids, &Map.get(actions, &1, :queued))
  end

  defp device_id(%Device{id: id}), do: id
  defp device_id(%{id: id}), do: id
  defp device_id(id) when is_binary(id), do: id

  defp command_result_ref(device, result) do
    case Devices.command_payload_for_result(device, result) do
      {:ok, %{} = payload} ->
        case {payload["type"] || payload[:type], payload["payload_ref"] || payload[:payload_ref]} do
          {"run_script", run_id} when is_binary(run_id) -> {:test, run_id}
          {"install_script", run_id} when is_binary(run_id) -> {:deploy, run_id}
          _ -> :ignore
        end

      _ ->
        :ignore
    end
  end

  defp get_test_run(id) do
    Domain.list_script_test_runs()
    |> elem(1)
    |> Enum.find(&(&1.id == id))
  end

  defp latest_test_run_by_id(id), do: get_test_run(id)

  defp get_deployment_run(id) do
    Domain.list_script_deployment_runs()
    |> elem(1)
    |> Enum.find(&(&1.id == id))
  end

  defp latest_deployment_run_by_id(id), do: get_deployment_run(id)

  defp attach_device_id(%Device{id: device_id}, results) do
    Enum.map(results, &Map.put(&1, "device_id", device_id))
  end

  defp system_session do
    %{"script_permissions" => %{"can_manage" => true}}
  end

  defp timestamp_client_result(%{status: :acknowledged} = attrs) do
    Map.put(attrs, :acknowledged_at, DateTime.utc_now())
  end

  defp timestamp_client_result(%{status: :failed} = attrs) do
    Map.put(attrs, :failed_at, DateTime.utc_now())
  end

  defp upsert_client_action(attrs) do
    case find_client_action(attrs) do
      nil -> Domain.create_script_client_action(attrs)
      action -> Domain.update_script_client_action(action, Map.take(attrs, client_action_update_keys()))
    end
  end

  defp client_action_update_keys do
    [:status, :command_ref, :payload_ref, :payload, :result_payload, :delivered_at, :acknowledged_at, :failed_at]
  end

  defp mark_client_actions_failed(:test, run_id) do
    Domain.list_script_client_actions()
    |> elem(1)
    |> Enum.filter(&(&1.kind == :test and &1.script_test_run_id == run_id))
    |> Enum.each(&Domain.update_script_client_action(&1, %{status: :failed}))
  end

  defp mark_client_actions_failed(:deploy, run_id) do
    Domain.list_script_client_actions()
    |> elem(1)
    |> Enum.filter(&(&1.kind == :deploy and &1.script_deployment_run_id == run_id))
    |> Enum.each(&Domain.update_script_client_action(&1, %{status: :failed}))
  end

  defp mark_client_actions_failed(_kind, _run_id), do: :ok

  defp find_client_action(%{kind: :test, script_test_run_id: run_id, device_id: device_id}) do
    Domain.list_script_client_actions()
    |> elem(1)
    |> Enum.find(&(&1.kind == :test and &1.script_test_run_id == run_id and &1.device_id == device_id))
  end

  defp find_client_action(%{kind: :deploy, script_deployment_run_id: run_id, device_id: device_id}) do
    Domain.list_script_client_actions()
    |> elem(1)
    |> Enum.find(&(&1.kind == :deploy and &1.script_deployment_run_id == run_id and &1.device_id == device_id))
  end

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

  defp broadcast_script(draft_id) do
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, "scripts:#{draft_id}", {:script_runs_changed, draft_id})
  end
end
