defmodule Nixstasis.E2E.Retention do
  @moduledoc false

  import Ecto.Query

  alias Nixstasis.E2E.{LogStore, Run, RunResult}
  alias Nixstasis.Repo

  @default_retention_days 14
  @default_max_run_count 2000
  @default_max_log_bytes 1_000_000_000

  def prune(opts, delete_runs_fun) when is_function(delete_runs_fun, 1) do
    policy = retention_policy(opts)

    if policy.enabled do
      run(policy, opts, delete_runs_fun)
    else
      empty_result()
    end
  end

  def empty_result, do: {:ok, %{pruned_runs: 0, pruned_log_bytes: 0, run_ids: []}}

  defp run(policy, opts, delete_runs_fun) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    run_items = retention_run_items()
    {run_ids_to_prune, pruned_log_bytes} = prune_candidates(run_items, policy, now)
    delete_candidates(run_ids_to_prune, pruned_log_bytes, policy, delete_runs_fun)
  end

  defp delete_candidates([], _pruned_log_bytes, _policy, _delete_runs_fun), do: empty_result()

  defp delete_candidates(run_ids, pruned_log_bytes, policy, delete_runs_fun) do
    with {:ok, deleted_count} <- delete_runs_fun.(run_ids) do
      :telemetry.execute(
        [:nixstasis, :e2e, :retention, :pruned],
        %{runs_pruned: deleted_count, log_bytes_pruned: pruned_log_bytes},
        %{policy: policy}
      )

      {:ok, %{pruned_runs: deleted_count, pruned_log_bytes: pruned_log_bytes, run_ids: run_ids}}
    end
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

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_), do: false
end
