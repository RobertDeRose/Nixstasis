defmodule Nixstasis.E2E.RetentionTest do
  use Nixstasis.DataCase

  alias Nixstasis.E2E
  alias Nixstasis.E2E.LogStore
  alias Nixstasis.E2E.Run
  alias Nixstasis.Repo

  setup do
    previous = Application.get_env(:nixstasis, :e2e)

    Application.put_env(:nixstasis, :e2e,
      allowed_env_labels: ["local"],
      protocol_versions: ["1"],
      environments: %{"local" => %{seed_script: "e2e/seed.exs"}},
      suites: %{"full" => ["auth"]},
      log_dir: "tmp/e2e-logs",
      retention: [
        enabled: true,
        retention_days: 14,
        max_run_count: 2000,
        max_log_bytes: 1_000_000_000
      ]
    )

    on_exit(fn ->
      File.rm_rf!("tmp/e2e-logs")

      if is_nil(previous) do
        Application.delete_env(:nixstasis, :e2e)
      else
        Application.put_env(:nixstasis, :e2e, previous)
      end
    end)

    :ok
  end

  test "prunes oldest runs when max_run_count is exceeded" do
    old_run =
      insert_run_with_inserted_at(
        %{
          suite_id: "full",
          journey_ids: ["auth"],
          environment_label: "local",
          trigger_source: "manual",
          protocol_version: "1",
          status: "passed",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
          run_metadata: %{}
        },
        DateTime.utc_now() |> DateTime.add(-3_600, :second)
      )

    new_run =
      insert_run_with_inserted_at(
        %{
          suite_id: "full",
          journey_ids: ["auth"],
          environment_label: "local",
          trigger_source: "manual",
          protocol_version: "1",
          status: "passed",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
          run_metadata: %{}
        },
        DateTime.utc_now()
      )

    {:ok, old_log} = LogStore.write_log(old_run.id, 1, "auth", "old")
    {:ok, new_log} = LogStore.write_log(new_run.id, 1, "auth", "new")

    insert_result(old_run.id, "auth", old_log)
    insert_result(new_run.id, "auth", new_log)

    assert {:ok, %{pruned_runs: 1, run_ids: [pruned_id]}} = E2E.prune_retention(max_run_count: 1)
    assert pruned_id == old_run.id
    refute Repo.get(Run, old_run.id)
    assert Repo.get(Run, new_run.id)
  end

  test "prunes runs older than retention_days" do
    very_old =
      insert_run_with_inserted_at(
        %{
          suite_id: "full",
          journey_ids: ["auth"],
          environment_label: "local",
          trigger_source: "manual",
          protocol_version: "1",
          status: "passed",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
          run_metadata: %{}
        },
        DateTime.utc_now() |> DateTime.add(-16 * 86_400, :second)
      )

    recent =
      insert_run_with_inserted_at(
        %{
          suite_id: "full",
          journey_ids: ["auth"],
          environment_label: "local",
          trigger_source: "manual",
          protocol_version: "1",
          status: "passed",
          started_at: DateTime.utc_now() |> DateTime.truncate(:second),
          finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
          run_metadata: %{}
        },
        DateTime.utc_now() |> DateTime.add(-60, :second)
      )

    assert {:ok, %{pruned_runs: 1, run_ids: [pruned_id]}} = E2E.prune_retention(retention_days: 14)
    assert pruned_id == very_old.id
    refute Repo.get(Run, very_old.id)
    assert Repo.get(Run, recent.id)
  end

  defp insert_run_with_inserted_at(attrs, inserted_at) do
    attrs
    |> Map.merge(%{
      inserted_at: inserted_at,
      updated_at: inserted_at
    })
    |> then(&Repo.insert!(struct(Run, &1)))
  end

  defp insert_result(run_id, journey_id, log_ref) do
    now = DateTime.utc_now()
    now_seconds = DateTime.truncate(now, :second)

    Repo.insert!(%Nixstasis.E2E.RunResult{
      run_id: run_id,
      journey_id: journey_id,
      status: "passed",
      log_ref: log_ref,
      started_at: now_seconds,
      finished_at: now_seconds,
      inserted_at: now,
      updated_at: now
    })
  end
end
