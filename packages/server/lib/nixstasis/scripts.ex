defmodule Nixstasis.Scripts do
  @moduledoc """
  Script workbench context.
  """

  alias Nixstasis.Devices
  alias Nixstasis.Devices.Device
  alias Nixstasis.Domain
  alias Nixstasis.Scripts.Audit
  alias Nixstasis.Scripts.Authorization
  require Ash.Query

  alias Nixstasis.Scripts.ScriptClientAction
  alias Nixstasis.Scripts.ScriptDeploymentRun
  alias Nixstasis.Scripts.ScriptDraft
  alias Nixstasis.Scripts.ScriptTestRun
  alias Nixstasis.Scripts.ScriptValidationRun
  alias Nixstasis.Scripts.ScriptVersion
  alias Nixstasis.Scripts.Validator

  @inline_script_payload_limit 4_096
  @script_history_limit 50
  @script_client_action_limit 500

  def list_drafts, do: Domain.list_script_drafts()

  @doc "Returns bounded, draft-scoped script history for the LiveView."
  def list_script_history(draft_id) do
    test_runs = list_script_test_runs_for_draft(draft_id)
    deployment_runs = list_script_deployment_runs_for_draft(draft_id)

    %{
      versions: list_script_versions_for_draft(draft_id),
      validation_runs: list_script_validation_runs_for_draft(draft_id),
      test_runs: test_runs,
      deployment_runs: deployment_runs,
      client_actions:
        list_script_client_actions_for_runs(
          Enum.map(test_runs, & &1.id),
          Enum.map(deployment_runs, & &1.id)
        )
    }
  end

  def list_script_versions_for_draft(draft_id) do
    ScriptVersion
    |> Ash.Query.filter(script_draft_id == ^draft_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@script_history_limit)
    |> Ash.Query.select([:id, :script_draft_id, :version, :status, :inserted_at])
    |> Ash.read!(domain: Domain)
  end

  def list_script_validation_runs_for_draft(draft_id) do
    ScriptValidationRun
    |> Ash.Query.filter(script_draft_id == ^draft_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@script_history_limit)
    |> Ash.Query.select([
      :id,
      :script_draft_id,
      :script_version_id,
      :status,
      :validated_at,
      :inserted_at
    ])
    |> Ash.read!(domain: Domain)
  end

  def list_script_test_runs_for_draft(draft_id) do
    ScriptTestRun
    |> Ash.Query.filter(script_draft_id == ^draft_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@script_history_limit)
    |> Ash.Query.select([
      :id,
      :script_draft_id,
      :script_version_id,
      :status,
      :started_at,
      :completed_at,
      :target_device_ids,
      :inserted_at
    ])
    |> Ash.read!(domain: Domain)
  end

  def list_script_deployment_runs_for_draft(draft_id) do
    ScriptDeploymentRun
    |> Ash.Query.filter(script_draft_id == ^draft_id)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@script_history_limit)
    |> Ash.Query.select([
      :id,
      :script_draft_id,
      :script_version_id,
      :status,
      :started_at,
      :completed_at,
      :target_device_ids,
      :inserted_at
    ])
    |> Ash.read!(domain: Domain)
  end

  def list_script_client_actions_for_runs([], []), do: %{}

  def list_script_client_actions_for_runs(test_run_ids, deployment_run_ids) do
    ScriptClientAction
    |> Ash.Query.filter(script_test_run_id in ^test_run_ids or script_deployment_run_id in ^deployment_run_ids)
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(@script_client_action_limit)
    |> Ash.Query.select([
      :id,
      :device_id,
      :script_test_run_id,
      :script_deployment_run_id,
      :kind,
      :status,
      :command_ref,
      :payload_ref,
      :result_payload,
      :inserted_at
    ])
    |> Ash.read!(domain: Domain)
    |> Enum.map(&bound_client_action_payload/1)
    |> Enum.group_by(fn action ->
      {action.kind, action.script_test_run_id || action.script_deployment_run_id}
    end)
  end

  defp bound_client_action_payload(action) do
    %{action | result_payload: bound_result_payload(action.result_payload)}
  end

  defp bound_result_payload(payload) when is_map(payload) do
    preview = inspect(payload, limit: 100, printable_limit: @inline_script_payload_limit)

    if byte_size(preview) > @inline_script_payload_limit do
      %{
        "truncated" => true,
        "preview" => binary_part(preview, 0, @inline_script_payload_limit)
      }
    else
      payload
    end
  end

  defp bound_result_payload(payload), do: payload

  def ingest_command_results(%Device{} = device, results) when is_list(results) do
    results
    |> Enum.group_by(&command_result_ref(device, &1))
    |> Enum.each(fn
      {{:test, run_id}, grouped_results} ->
        with %ScriptTestRun{} = run <- get_test_run(run_id) do
          ingest_test_results_from_device(device, run, attach_device_id(device, grouped_results))
        end

      {{:deploy, run_id}, grouped_results} ->
        with %ScriptDeploymentRun{} = run <- get_deployment_run(run_id) do
          ingest_deployment_results_from_device(device, run, attach_device_id(device, grouped_results))
        end

      _ ->
        :ok
    end)
  end

  def ingest_command_results(_device, _results), do: :ok

  def create_draft(session, attrs) do
    with true <- Authorization.can_create?(session),
         {:ok, actor_id} <- Authorization.actor_id(session) do
      result = Domain.create_script_draft(attrs)
      audit_result(result, :draft_created, attrs, actor_id)
      result
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_draft(session, %ScriptDraft{} = draft, attrs) do
    with true <- Authorization.can_edit?(session),
         {:ok, actor_id} <- Authorization.actor_id(session) do
      result = Domain.update_script_draft(draft, attrs)
      audit_result(result, :draft_updated, Map.merge(%{draft_id: draft.id}, attrs), actor_id)
      result
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  def render_draft(%ScriptDraft{front_matter: front_matter, body: body}),
    do: Validator.render_stary(front_matter, body)

  def validate_draft(session, %ScriptDraft{} = draft) do
    with true <- Authorization.can_validate?(session),
         {:ok, actor_id} <- Authorization.actor_id(session) do
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
          persist_validated_draft(draft, version, payload, actor_id)

        {:error, reason} ->
          record_failed_validation(draft, rendered, reason, actor_id)
      end
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_validated_draft(%ScriptDraft{} = draft, version, payload, actor_id) do
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
          audit_result(
            result,
            :validation_passed,
            %{script_draft_id: draft.id, script_version_id: script_version.id},
            actor_id
          )

          broadcast_script(draft.id)
          {:ok, result}
        end

      {:error, reason} ->
        record_failed_validation(draft, payload.rendered_content, reason, actor_id)
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

  defp record_failed_validation(%ScriptDraft{} = draft, rendered, reason, actor_id) do
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

    Audit.emit(:validation_failed, actor_id, %{script_draft_id: draft.id, reason: message})
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
         {:ok, actor_id} <- Authorization.actor_id(session),
         device_ids <- Enum.map(devices, &device_id/1),
         true <- Authorization.can_target_devices?(session, device_ids),
         :ok <- require_validated_version(version) do
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

      Audit.emit(
        :test_queued,
        actor_id,
        %{
          script_draft_id: draft.id,
          script_version_id: version.id,
          target_device_ids: device_ids
        }
      )

      broadcast_script(draft.id)
      {:ok, test_run}
    else
      {:error, :unvalidated_version} -> {:error, :unvalidated_version}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unauthorized}
    end
  end

  def ingest_test_results(session, %ScriptTestRun{} = test_run, results) when is_list(results) do
    with true <- Authorization.can_test?(session),
         {:ok, actor_id} <- Authorization.actor_id(session) do
      ingest_test_results_with_actor(test_run, results, :operator, actor_id)
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ingest_test_results_from_device(%Device{} = device, test_run, results) do
    ingest_test_results_with_actor(test_run, results, :device, device.id)
  end

  defp ingest_test_results_with_actor(%ScriptTestRun{} = test_run, results, actor_type, actor_id)
       when is_list(results) do
    with %ScriptTestRun{status: :running} = current_run <- latest_test_run_by_id(test_run.id) do
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

        emit_result_audit(actor_type, :test_client_result, actor_id, %{
          script_test_run_id: test_run.id,
          device_id: device_id,
          status: status
        })
      end)

      final_status = test_run_status(current_run)
      attrs = run_update_attrs(final_status)
      result = Domain.update_script_test_run(current_run, attrs)

      if final_status != :running do
        emit_result_audit(actor_type, :test_completed, actor_id, %{
          script_test_run_id: test_run.id,
          status: final_status
        })
      end

      broadcast_script(test_run.script_draft_id)
      result
    else
      %ScriptTestRun{} = run -> {:ok, run}
      _ -> ingest_result_error(actor_type)
    end
  end

  def queue_deployment(session, %ScriptDraft{} = draft, %ScriptVersion{} = version, devices)
      when is_list(devices) do
    with true <- Authorization.can_deploy?(session),
         {:ok, actor_id} <- Authorization.actor_id(session),
         device_ids <- Enum.map(devices, &device_id/1),
         true <- Authorization.can_target_devices?(session, device_ids),
         :ok <- require_validated_version(version) do
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

      Audit.emit(
        :deployment_queued,
        actor_id,
        %{
          script_draft_id: draft.id,
          script_version_id: version.id,
          target_device_ids: device_ids
        }
      )

      broadcast_script(draft.id)
      {:ok, deployment_run}
    else
      {:error, :unvalidated_version} -> {:error, :unvalidated_version}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unauthorized}
    end
  end

  def ingest_deployment_results(session, %ScriptDeploymentRun{} = run, results) when is_list(results) do
    with true <- Authorization.can_deploy?(session),
         {:ok, actor_id} <- Authorization.actor_id(session) do
      ingest_deployment_results_with_actor(run, results, :operator, actor_id)
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ingest_deployment_results_from_device(%Device{} = device, run, results) do
    ingest_deployment_results_with_actor(run, results, :device, device.id)
  end

  defp ingest_deployment_results_with_actor(%ScriptDeploymentRun{} = run, results, actor_type, actor_id)
       when is_list(results) do
    with %ScriptDeploymentRun{status: :running} = current_run <- latest_deployment_run_by_id(run.id) do
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

        emit_result_audit(actor_type, :deployment_client_result, actor_id, %{
          script_deployment_run_id: run.id,
          device_id: device_id,
          status: status
        })
      end)

      final_status = deployment_run_status(current_run)
      attrs = run_update_attrs(final_status)
      result = Domain.update_script_deployment_run(current_run, attrs)

      if final_status != :running do
        emit_result_audit(actor_type, :deployment_completed, actor_id, %{
          script_deployment_run_id: run.id,
          status: final_status
        })
      end

      broadcast_script(run.script_draft_id)
      result
    else
      %ScriptDeploymentRun{} = run -> {:ok, run}
      _ -> ingest_result_error(actor_type)
    end
  end

  def cancel_test_run(session, %ScriptTestRun{} = run) do
    with true <- Authorization.can_test?(session),
         {:ok, actor_id} <- Authorization.actor_id(session),
         %ScriptTestRun{} = current_run <- latest_test_run_by_id(run.id),
         true <- current_run.status in [:pending, :running] do
      result = Domain.update_script_test_run(current_run, %{status: :failed, completed_at: DateTime.utc_now()})
      mark_client_actions_failed(:test, current_run.id)
      audit_result(result, :test_cancelled, %{script_test_run_id: run.id}, actor_id)
      broadcast_script(run.script_draft_id)
      result
    else
      false -> {:error, :not_running}
      %ScriptTestRun{} -> {:error, :not_running}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unauthorized}
    end
  end

  def cancel_deployment_run(session, %ScriptDeploymentRun{} = run) do
    with true <- Authorization.can_deploy?(session),
         {:ok, actor_id} <- Authorization.actor_id(session),
         %ScriptDeploymentRun{} = current_run <- latest_deployment_run_by_id(run.id),
         true <- current_run.status in [:pending, :running] do
      result = Domain.update_script_deployment_run(current_run, %{status: :failed, completed_at: DateTime.utc_now()})
      mark_client_actions_failed(:deploy, current_run.id)
      audit_result(result, :deployment_cancelled, %{script_deployment_run_id: run.id}, actor_id)
      broadcast_script(run.script_draft_id)
      result
    else
      false -> {:error, :not_running}
      %ScriptDeploymentRun{} -> {:error, :not_running}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :unauthorized}
    end
  end

  def archive_draft(session, %ScriptDraft{} = draft) do
    with true <- Authorization.can_archive?(session),
         {:ok, actor_id} <- Authorization.actor_id(session) do
      result = Domain.update_script_draft(draft, %{status: :archived})
      audit_result(result, :draft_archived, %{draft_id: draft.id}, actor_id)
      result
    else
      false -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
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

  defp emit_result_audit(:operator, action, actor_id, attrs), do: Audit.emit(action, actor_id, attrs)
  defp emit_result_audit(:device, action, device_id, attrs), do: Audit.emit_device(action, device_id, attrs)

  defp ingest_result_error(:operator), do: {:error, :unauthorized}
  defp ingest_result_error(:device), do: {:error, :not_running}

  defp audit_result({:ok, value}, action, attrs, actor_id) do
    Audit.emit(action, actor_id, Map.put(attrs, :resource_id, Map.get(value, :id)))
  end

  defp audit_result(_, _action, _attrs, _actor_id), do: :ok

  defp broadcast_script(draft_id) do
    Phoenix.PubSub.broadcast(Nixstasis.PubSub, "scripts:#{draft_id}", {:script_runs_changed, draft_id})
  end
end
