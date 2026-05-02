defmodule Nixstasis.E2ETest do
  use Nixstasis.DataCase

  import Ecto.Query

  alias Nixstasis.E2E
  alias Nixstasis.E2E.EnvironmentLock
  alias Nixstasis.E2E.LogStore
  alias Nixstasis.E2E.Run
  alias Nixstasis.E2E.RunResult
  alias Nixstasis.Repo

  setup do
    previous = Application.get_env(:nixstasis, :e2e)

    Application.put_env(:nixstasis, :e2e,
      allowed_env_labels: ["local", "qa"],
      environments: %{
        "local" => %{seed_script: "priv/e2e/seed.exs"},
        "qa" => %{seed_script: "priv/e2e/seed.exs"}
      },
      suites: %{"full" => ["auth"]},
      log_dir: "tmp/e2e-logs",
      protocol_versions: ["1"]
    )

    on_exit(fn ->
      File.rm_rf!("tmp/e2e-logs")
      Repo.delete_all(EnvironmentLock)

      if is_nil(previous) do
        Application.delete_env(:nixstasis, :e2e)
      else
        Application.put_env(:nixstasis, :e2e, previous)
      end
    end)

    :ok
  end

  test "delete_runs removes runs, results, and log files" do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1"
      })

    {:ok, log_path} = LogStore.write_log(run.id, "auth", "{\"message\":\"ok\"}\n")

    assert {:ok, _} =
             E2E.submit_results(run.id, [
               %{
                 journey_id: "auth",
                 status: "passed",
                 log_ref: log_path,
                 duration_ms: 10
               }
             ])

    run_dir = Path.dirname(log_path)
    assert File.dir?(run_dir)
    assert {:ok, 1} = E2E.delete_runs([run.id])

    refute Repo.get(Run, run.id)
    assert [] = Repo.all(from result in RunResult, where: result.run_id == ^run.id)
    refute File.exists?(log_path)
    refute File.dir?(run_dir)
  end

  test "create_run reuses run for same environment + idempotency key within ttl" do
    attrs = %{
      suite_id: "full",
      environment_label: "local",
      trigger_source: "manual",
      protocol_version: "1",
      idempotency_key: "same-request"
    }

    assert {:ok, run1} = E2E.create_run(attrs)
    assert {:ok, run2} = E2E.create_run(attrs)
    assert run1.id == run2.id
  end

  test "create_run with same idempotency key in different environments creates separate runs" do
    attrs = %{
      suite_id: "full",
      trigger_source: "manual",
      protocol_version: "1",
      idempotency_key: "cross-env-key"
    }

    assert {:ok, local_run} = E2E.create_run(Map.put(attrs, :environment_label, "local"))
    assert {:ok, qa_run} = E2E.create_run(Map.put(attrs, :environment_label, "qa"))
    assert local_run.id != qa_run.id
  end

  test "create_run returns environment_locked while another run is active in same environment" do
    attrs = %{
      suite_id: "full",
      environment_label: "local",
      trigger_source: "manual",
      protocol_version: "1"
    }

    assert {:ok, _run} = E2E.create_run(attrs)
    assert {:error, {:environment_locked, message}} = E2E.create_run(attrs)
    assert message =~ "already has an active E2E run"
  end

  test "create_run fails when seed script is missing" do
    previous = Application.get_env(:nixstasis, :e2e)

    Application.put_env(
      :nixstasis,
      :e2e,
      previous
      |> Keyword.put(:environments, %{"local" => %{seed_script: "priv/e2e/missing_seed.exs"}})
      |> Keyword.put(:allowed_env_labels, ["local"])
    )

    on_exit(fn ->
      Application.put_env(:nixstasis, :e2e, previous)
    end)

    assert {:error, {:seed_failed, message}} =
             E2E.create_run(%{
               suite_id: "full",
               environment_label: "local",
               trigger_source: "manual",
               protocol_version: "1"
             })

    assert message =~ "Seed script not found"
  end

  test "create_run rejects invalid action expectation pairs before run is accepted" do
    previous = Application.get_env(:nixstasis, :e2e)

    Application.put_env(
      :nixstasis,
      :e2e,
      previous
      |> Keyword.put(:suites, %{"invalid" => ["missing_journey"]})
      |> Keyword.put(:allowed_env_labels, ["local"])
      |> Keyword.put(:environments, %{"local" => %{seed_script: "priv/e2e/seed.exs"}})
    )

    on_exit(fn ->
      Application.put_env(:nixstasis, :e2e, previous)
    end)

    assert {:error, {:invalid_action_expectation, message}} =
             E2E.create_run(%{
               suite_id: "invalid",
               environment_label: "local",
               trigger_source: "manual",
               protocol_version: "1"
             })

    assert message =~ "Journey file for 'missing_journey' was not found"
  end
end
