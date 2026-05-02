defmodule Nixstasis.E2E do
  @moduledoc """
  Context for managing end-to-end test runs.
  """

  import Ecto.Query

  alias Nixstasis.E2E.{
    DataPolicy,
    EnvironmentLocks,
    ExpectationRegistry,
    JourneySelection,
    LogStore,
    Protocol,
    Run,
    RunResult
  }

  alias Nixstasis.Repo

  @idempotency_ttl_seconds 3600
  @default_retention_days 14
  @default_max_run_count 2000
  @default_max_log_bytes 1_000_000_000

  def list_runs do
    Repo.all(from run in Run, order_by: [desc: run.inserted_at])
  end

  def list_suites do
    Application.get_env(:nixstasis, :e2e, [])
    |> Keyword.get(:suites, %{})
    |> Enum.map(fn {suite_id, journey_ids} ->
      %{
        id: suite_id,
        journey_ids: journey_ids
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  def get_run!(id), do: Repo.get!(Run, id)

  def get_run(id) do
    case Repo.get(Run, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  def prune_retention(opts \\ []) do
    policy = retention_policy(opts)

    if policy.enabled, do: run_retention(policy, opts), else: empty_retention_result()
  end

  def list_results(run_id) do
    Repo.all(from result in RunResult, where: result.run_id == ^run_id, order_by: [asc: result.inserted_at])
  end

  def create_run(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)
    emit_event([:run, :create, :attempt], %{count: 1}, %{environment_label: attrs.environment_label})

    with :ok <- validate_legacy_fields(attrs),
         :ok <- DataPolicy.validate_environment(attrs.environment_label),
         {:ok, protocol_version} <- Protocol.validate(attrs.protocol_version),
         {:ok, journey_ids} <- JourneySelection.resolve(attrs.suite_id, attrs.journey_ids),
         :ok <- ExpectationRegistry.validate_journeys(journey_ids),
         {:ok, run} <- create_or_reuse_run(attrs, journey_ids, protocol_version) do
      emit_event([:run, :create, :success], %{count: 1}, %{run_id: run.id, environment_label: run.environment_label})
      {:ok, run}
    else
      {:error, {:environment_locked, _} = reason} ->
        emit_event([:run, :lock, :conflict], %{count: 1}, %{environment_label: attrs.environment_label})
        {:error, reason}

      {:error, {:protocol_mismatch, _} = reason} ->
        emit_event([:run, :protocol, :mismatch], %{count: 1}, %{})
        {:error, reason}

      {:error, {:invalid_action_expectation, _} = reason} ->
        {:error, reason}

      {:error, {:seed_failed, _} = reason} ->
        {:error, reason}

      {:error, {:database_error, _}} = error ->
        error

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, message} when is_binary(message) ->
        {:error, {:invalid, message}}

      other ->
        other
    end
  end

  def cancel_run(id) when is_binary(id) do
    with {:ok, run} <- get_run(id) do
      case run
           |> Run.changeset(%{status: "cancelled", finished_at: DateTime.utc_now()})
           |> Repo.update() do
        {:ok, updated} ->
          EnvironmentLocks.release(updated.environment_label)
          {:ok, updated}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def delete_runs(run_ids) when is_list(run_ids) do
    ids =
      run_ids
      |> Enum.map(&normalize_run_id/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [] do
      {:ok, 0}
    else
      log_refs = list_log_refs(ids)

      case Repo.delete_all(from(run in Run, where: run.id in ^ids)) do
        {count, _} ->
          Enum.each(log_refs, &delete_log_ref/1)
          Enum.each(ids, &delete_run_log_dir/1)
          Enum.each(ids, &EnvironmentLocks.release_by_run/1)
          {:ok, count}

        _ ->
          {:error, {:database_error, :delete_failed}}
      end
    end
  end

  def record_result(run_id, journey_id, attrs) do
    result_attrs =
      attrs
      |> Map.put(:run_id, run_id)
      |> Map.put(:journey_id, journey_id)

    case Repo.get_by(RunResult, run_id: run_id, journey_id: journey_id) do
      nil ->
        %RunResult{}
        |> RunResult.changeset(result_attrs)
        |> Repo.insert()

      %RunResult{} = existing ->
        existing
        |> RunResult.changeset(result_attrs)
        |> Repo.update()
    end
  end

  def submit_results(run_id, results) when is_list(results) do
    with {:ok, run} <- get_run(run_id),
         :ok <- validate_results_payload(run, results) do
      submit_results_transaction(run, run_id, results)
      |> case do
        {:ok, payload} -> {:ok, payload}
        {:error, {:invalid, changeset}} -> {:error, {:invalid, format_changeset(changeset)}}
        {:error, reason} -> {:error, {:database_error, reason}}
      end
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, {:invalid, _}} = error -> error
      {:error, message} when is_binary(message) -> {:error, {:invalid, message}}
      other -> other
    end
  end

  def store_log(run_id, journey_id, content) do
    LogStore.write_log(run_id, journey_id, content)
  end

  def fetch_result_log(run_id, journey_id) when is_binary(run_id) and is_binary(journey_id) do
    with {:ok, _run} <- get_run(run_id),
         %RunResult{} = result <- Repo.get_by(RunResult, run_id: run_id, journey_id: journey_id),
         false <- blank?(result.log_ref),
         {:ok, content} <- LogStore.read_log(result.log_ref) do
      {:ok, content}
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
      true -> {:error, {:log_unavailable, "Log file reference is missing for this journey."}}
      {:error, :log_unavailable} -> {:error, {:log_unavailable, "Log is unavailable (possibly pruned or deleted)."}}
      {:error, :enoent} -> {:error, {:log_unavailable, "Log is unavailable (possibly pruned or deleted)."}}
      {:error, :outside_allowed_dirs} -> {:error, {:log_unavailable, "Log path is not accessible."}}
      {:error, {:read_failed, reason}} -> {:error, {:log_unavailable, "Failed to read log: #{inspect(reason)}"}}
    end
  end

  def fetch_result_log(_run_id, _journey_id), do: {:error, :not_found}

  defp create_or_reuse_run(attrs, journey_ids, protocol_version) do
    case fetch_idempotent_run(attrs.environment_label, attrs.idempotency_key) do
      %Run{} = run ->
        emit_event([:run, :idempotency, :hit], %{count: 1}, %{run_id: run.id, environment_label: run.environment_label})
        {:ok, run}

      nil ->
        emit_event([:run, :idempotency, :miss], %{count: 1}, %{environment_label: attrs.environment_label})
        create_new_run(attrs, journey_ids, protocol_version)
    end
  end

  defp create_new_run(attrs, journey_ids, protocol_version) do
    with {:ok, _lock} <- EnvironmentLocks.acquire(attrs.environment_label),
         :ok <- validate_preconditions(attrs.environment_label),
         {:ok, run} <- persist_run(attrs, journey_ids, protocol_version) do
      :ok = EnvironmentLocks.assign_run(attrs.environment_label, run.id)
      {:ok, run}
    else
      {:error, {:environment_locked, _} = reason} ->
        {:error, reason}

      {:error, reason} ->
        EnvironmentLocks.release(attrs.environment_label)
        {:error, reason}
    end
  end

  defp persist_submitted_result!(run_id, result, now) do
    journey_id = fetch_result_attr(result, :journey_id)
    status = fetch_result_attr(result, :status)
    attrs = submitted_result_attrs(result, status, now)

    case record_result(run_id, journey_id, attrs) do
      {:ok, _result} ->
        :ok

      {:error, changeset} ->
        Repo.rollback({:invalid, changeset})
    end
  end

  defp submitted_result_attrs(result, status, now) do
    %{
      status: status,
      failure_step: fetch_result_attr(result, :failure_step),
      failure_reason: fetch_result_attr(result, :failure_reason),
      log_ref: fetch_result_attr(result, :log_ref),
      duration_ms: fetch_result_attr(result, :duration_ms),
      finished_at: if(final_status?(status), do: now, else: nil)
    }
  end

  defp run_finished_at(status, now) do
    if final_run_status?(status), do: now, else: nil
  end

  defp list_log_refs(run_ids) do
    Repo.all(
      from result in RunResult,
        where: result.run_id in ^run_ids,
        select: result.log_ref
    )
    |> Enum.reject(&blank?/1)
    |> Enum.uniq()
  end

  defp delete_log_ref(log_ref) do
    case LogStore.delete_log(log_ref) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp delete_run_log_dir(run_id) do
    case LogStore.delete_run_dir(run_id) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp persist_run(attrs, journey_ids, protocol_version) do
    idempotency_expires_at = idempotency_expires_at(attrs.idempotency_key)

    Repo.transaction(fn ->
      {:ok, run} =
        %Run{}
        |> Run.changeset(%{
          suite_id: attrs.suite_id,
          journey_ids: journey_ids,
          environment_label: attrs.environment_label,
          trigger_source: attrs.trigger_source,
          protocol_version: protocol_version,
          idempotency_key: attrs.idempotency_key,
          idempotency_expires_at: idempotency_expires_at,
          status: "queued",
          started_at: DateTime.utc_now(),
          run_metadata: attrs.run_metadata
        })
        |> Repo.insert()

      results =
        Enum.map(journey_ids, fn journey_id ->
          %{
            run_id: run.id,
            journey_id: journey_id,
            status: "queued"
          }
        end)

      Repo.insert_all(RunResult, results)
      run
    end)
    |> case do
      {:ok, run} -> {:ok, run}
      {:error, reason} -> {:error, {:database_error, reason}}
    end
  end

  defp validate_preconditions(environment_label) do
    envs =
      Application.get_env(:nixstasis, :e2e, [])
      |> Keyword.get(:environments, %{})

    with {:ok, env} <- fetch_env(envs, environment_label),
         {:ok, seed_path} <- fetch_seed_path(env, environment_label) do
      started_at = System.monotonic_time(:millisecond)

      case run_seed_script(seed_path) do
        :ok ->
          emit_event(
            [:seed, :success],
            %{duration_ms: System.monotonic_time(:millisecond) - started_at},
            %{environment_label: environment_label}
          )

          :ok

        {:error, _} = error ->
          emit_event(
            [:seed, :failure],
            %{duration_ms: System.monotonic_time(:millisecond) - started_at},
            %{environment_label: environment_label}
          )

          error
      end
    end
  end

  defp fetch_env(envs, environment_label) do
    case Map.fetch(envs, environment_label) do
      {:ok, env} -> {:ok, env}
      :error -> {:error, {:invalid, "Environment '#{environment_label}' is not configured or ready."}}
    end
  end

  defp fetch_seed_path(env, environment_label) do
    case Map.get(env, :seed_script) do
      seed_script when is_binary(seed_script) ->
        seed_path = Path.expand(seed_script, File.cwd!())

        if File.exists?(seed_path) do
          {:ok, seed_path}
        else
          missing_seed_error(environment_label)
        end

      _ ->
        missing_seed_error(environment_label)
    end
  end

  defp missing_seed_error(environment_label) do
    {:error,
     {:seed_failed, "Baseline test data is missing. Seed script not found for environment '#{environment_label}'."}}
  end

  defp normalize_attrs(attrs) do
    %{
      suite_id: fetch_attr(attrs, "suite_id", :suite_id),
      journey_ids: fetch_attr(attrs, "journey_ids", :journey_ids, []),
      environment_label: fetch_attr(attrs, "environment_label", :environment_label),
      trigger_source: fetch_attr(attrs, "trigger_source", :trigger_source),
      protocol_version: fetch_attr(attrs, "protocol_version", :protocol_version),
      idempotency_key: attrs |> fetch_attr("idempotency_key", :idempotency_key) |> normalize_idempotency_key(),
      run_metadata: fetch_attr(attrs, "metadata", :run_metadata, %{}),
      legacy_client_version: fetch_attr(attrs, "client_version", :client_version),
      legacy_server_version: fetch_attr(attrs, "server_version", :server_version)
    }
  end

  defp fetch_attr(attrs, key, atom_key, default \\ nil) do
    case Map.get(attrs, key) do
      nil -> Map.get(attrs, atom_key, default)
      value -> value
    end
  end

  defp run_seed_script(path) do
    Code.eval_file(path)
    :ok
  rescue
    error -> {:error, {:seed_failed, "Failed to reset baseline data: #{Exception.message(error)}"}}
  end

  defp validate_results_payload(%Run{} = run, results) do
    cond do
      results == [] ->
        {:error, {:invalid, "Results payload cannot be empty."}}

      Enum.any?(results, fn result -> blank?(fetch_result_attr(result, :journey_id)) end) ->
        {:error, {:invalid, "Each result must include a journey_id."}}

      Enum.any?(results, fn result -> blank?(fetch_result_attr(result, :status)) end) ->
        {:error, {:invalid, "Each result must include a status."}}

      true ->
        selected = Enum.map(results, &fetch_result_attr(&1, :journey_id))
        invalid = selected -- run.journey_ids

        if invalid == [] do
          :ok
        else
          {:error, {:invalid, "Unknown journeys provided: #{Enum.join(invalid, ", ")}."}}
        end
    end
  end

  defp fetch_result_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp normalize_run_id(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_run_id(_), do: nil

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false

  defp final_status?(status) when status in ["passed", "failed", "blocked", "cancelled", "skipped"],
    do: true

  defp final_status?(_), do: false

  defp final_run_status?(status) when status in ["passed", "failed", "blocked", "cancelled"], do: true
  defp final_run_status?(_), do: false

  defp derive_run_status(results) do
    counts = Enum.frequencies_by(results, & &1.status)
    total = length(results)

    cond do
      Map.get(counts, "failed", 0) > 0 -> "failed"
      Map.get(counts, "running", 0) > 0 -> "running"
      Map.get(counts, "queued", 0) > 0 -> "running"
      Map.get(counts, "blocked", 0) > 0 -> "blocked"
      Map.get(counts, "skipped", 0) > 0 -> "blocked"
      Map.get(counts, "cancelled", 0) == total and total > 0 -> "cancelled"
      true -> "passed"
    end
  end

  defp format_changeset(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)

    inspect(errors)
  end

  defp validate_legacy_fields(%{legacy_client_version: nil, legacy_server_version: nil}), do: :ok

  defp validate_legacy_fields(_attrs) do
    {:error,
     {:protocol_mismatch,
      "Legacy fields client_version/server_version are no longer supported. Use X-E2E-Protocol-Version."}}
  end

  defp normalize_idempotency_key(nil), do: nil

  defp normalize_idempotency_key(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_idempotency_key(_value), do: nil

  defp idempotency_expires_at(nil), do: nil

  defp idempotency_expires_at(_key) do
    DateTime.utc_now()
    |> DateTime.add(@idempotency_ttl_seconds, :second)
  end

  defp fetch_idempotent_run(_environment_label, nil), do: nil

  defp fetch_idempotent_run(environment_label, idempotency_key) do
    now = DateTime.utc_now()

    from(run in Run,
      where:
        run.environment_label == ^environment_label and run.idempotency_key == ^idempotency_key and
          run.idempotency_expires_at > ^now,
      order_by: [desc: run.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  defp emit_event(event_suffix, measurements, metadata) do
    :telemetry.execute([:nixstasis, :e2e | event_suffix], measurements, metadata)
  end

  defp run_retention(policy, opts) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    run_items = retention_run_items()
    {run_ids_to_prune, pruned_log_bytes} = prune_candidates(run_items, policy, now)
    delete_retention_candidates(run_ids_to_prune, pruned_log_bytes, policy)
  end

  defp delete_retention_candidates([], _pruned_log_bytes, _policy), do: empty_retention_result()

  defp delete_retention_candidates(run_ids, pruned_log_bytes, policy) do
    with {:ok, deleted_count} <- delete_runs(run_ids) do
      emit_event(
        [:retention, :pruned],
        %{runs_pruned: deleted_count, log_bytes_pruned: pruned_log_bytes},
        %{policy: policy}
      )

      {:ok, %{pruned_runs: deleted_count, pruned_log_bytes: pruned_log_bytes, run_ids: run_ids}}
    end
  end

  defp empty_retention_result, do: {:ok, %{pruned_runs: 0, pruned_log_bytes: 0, run_ids: []}}

  defp submit_results_transaction(run, run_id, results) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      Enum.each(results, &persist_submitted_result!(run_id, &1, now))

      updated_results = list_results(run_id)
      status = derive_run_status(updated_results)
      finished_at = run_finished_at(status, now)

      {:ok, updated_run} =
        run
        |> Run.changeset(%{status: status, finished_at: finished_at})
        |> Repo.update()

      release_run_lock_if_final(updated_run, status)
      %{run: updated_run, results: updated_results}
    end)
  end

  defp release_run_lock_if_final(%Run{} = run, status) do
    if final_run_status?(status), do: EnvironmentLocks.release(run.environment_label)
  end

  defp retention_policy(opts) do
    retention =
      Application.get_env(:nixstasis, :e2e, [])
      |> Keyword.get(:retention, [])

    %{
      enabled: Keyword.get(opts, :enabled, Keyword.get(retention, :enabled, true)),
      retention_days:
        coerce_positive_integer(
          Keyword.get(opts, :retention_days, Keyword.get(retention, :retention_days, @default_retention_days)),
          @default_retention_days
        ),
      max_run_count:
        coerce_positive_integer(
          Keyword.get(opts, :max_run_count, Keyword.get(retention, :max_run_count, @default_max_run_count)),
          @default_max_run_count
        ),
      max_log_bytes:
        coerce_non_negative_integer(
          Keyword.get(opts, :max_log_bytes, Keyword.get(retention, :max_log_bytes, @default_max_log_bytes)),
          @default_max_log_bytes
        )
    }
  end

  defp retention_run_items do
    runs =
      Repo.all(
        from run in Run,
          order_by: [asc: run.inserted_at, asc: run.id],
          select: %{id: run.id, inserted_at: run.inserted_at}
      )

    refs_by_run = run_log_refs_map(Enum.map(runs, & &1.id))

    Enum.map(runs, fn run ->
      refs = Map.get(refs_by_run, run.id, [])

      %{
        id: run.id,
        inserted_at: run.inserted_at,
        log_bytes: Enum.reduce(refs, 0, fn ref, acc -> acc + log_ref_size(ref) end)
      }
    end)
  end

  defp run_log_refs_map([]), do: %{}

  defp run_log_refs_map(run_ids) do
    Repo.all(
      from result in RunResult,
        where: result.run_id in ^run_ids,
        select: {result.run_id, result.log_ref}
    )
    |> Enum.reduce(%{}, fn {run_id, log_ref}, acc ->
      if blank?(log_ref) do
        acc
      else
        Map.update(acc, run_id, MapSet.new([log_ref]), &MapSet.put(&1, log_ref))
      end
    end)
    |> Enum.into(%{}, fn {run_id, refs} -> {run_id, MapSet.to_list(refs)} end)
  end

  defp log_ref_size(nil), do: 0

  defp log_ref_size(log_ref) do
    case LogStore.log_size(log_ref) do
      {:ok, size} when is_integer(size) and size > 0 -> size
      _ -> 0
    end
  end

  defp prune_candidates(run_items, policy, now) do
    total_runs = length(run_items)
    total_log_bytes = Enum.reduce(run_items, 0, &(&1.log_bytes + &2))
    cutoff = DateTime.add(now, -policy.retention_days * 86_400, :second)

    {candidates, _remaining_runs, _remaining_log_bytes} =
      Enum.reduce(run_items, {[], total_runs, total_log_bytes}, fn item,
                                                                   {to_prune, remaining_runs, remaining_log_bytes} ->
        prune_for_age = stale_run?(item, cutoff)
        prune_for_count = remaining_runs > policy.max_run_count
        prune_for_size = remaining_log_bytes > policy.max_log_bytes

        if prune_for_age or prune_for_count or prune_for_size do
          updated_log_bytes = max(remaining_log_bytes - item.log_bytes, 0)
          {[item | to_prune], remaining_runs - 1, updated_log_bytes}
        else
          {to_prune, remaining_runs, remaining_log_bytes}
        end
      end)

    run_ids = candidates |> Enum.reverse() |> Enum.map(& &1.id)
    pruned_log_bytes = Enum.reduce(candidates, 0, &(&1.log_bytes + &2))
    {run_ids, pruned_log_bytes}
  end

  defp stale_run?(%{inserted_at: %DateTime{} = inserted_at}, cutoff) do
    DateTime.compare(inserted_at, cutoff) == :lt
  end

  defp stale_run?(_item, _cutoff), do: false

  defp coerce_positive_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp coerce_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp coerce_positive_integer(_value, default), do: default

  defp coerce_non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp coerce_non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> default
    end
  end

  defp coerce_non_negative_integer(_value, default), do: default
end
