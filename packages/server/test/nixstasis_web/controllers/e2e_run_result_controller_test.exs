defmodule NixstasisWeb.E2ERunResultControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.E2E
  alias Nixstasis.E2E.LogStore

  setup do
    previous = Application.get_env(:nixstasis, :e2e)
    previous_context = Application.get_env(:nixstasis, :e2e_context)

    Application.put_env(:nixstasis, :e2e,
      allowed_env_labels: ["local"],
      environments: %{"local" => %{seed_script: "priv/e2e/seed.exs"}},
      suites: %{"full" => ["auth"]},
      log_dir: "tmp/e2e-logs"
    )

    on_exit(fn ->
      File.rm_rf!("tmp/e2e-logs")

      if is_nil(previous) do
        Application.delete_env(:nixstasis, :e2e)
      else
        Application.put_env(:nixstasis, :e2e, previous)
      end

      if is_nil(previous_context) do
        Application.delete_env(:nixstasis, :e2e_context)
      else
        Application.put_env(:nixstasis, :e2e_context, previous_context)
      end
    end)

    :ok
  end

  test "Given a run, when GET /e2e/runs/:id/results, then results are returned", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1"
      })

    conn = get(conn, ~p"/e2e/runs/#{run.id}/results")

    assert %{"data" => results} = json_response(conn, 200)
    assert length(results) == 1
    assert hd(results)["journey_id"] == "auth"
  end

  test "Given results payload, when POST /e2e/runs/:id/results, then results are stored", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1"
      })

    payload = %{
      "results" => [
        %{
          "journey_id" => "auth",
          "status" => "passed",
          "duration_ms" => 1200
        }
      ]
    }

    conn = post(conn, ~p"/e2e/runs/#{run.id}/results", payload)

    assert %{"data" => results} = json_response(conn, 202)
    assert length(results) == 1
    assert hd(results)["status"] == "passed"

    {:ok, updated_run} = E2E.get_run(run.id)
    assert updated_run.status == "passed"
  end

  test "Given missing journey log, when GET /e2e/runs/:id/results/:journey_id/log, then log_unavailable is returned", %{
    conn: conn
  } do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1"
      })

    assert {:ok, _} =
             E2E.submit_results(run.id, [
               %{
                 journey_id: "auth",
                 status: "passed",
                 duration_ms: 1200
               }
             ])

    conn = get(conn, ~p"/e2e/runs/#{run.id}/results/auth/log")

    assert %{"error" => %{"code" => "log_unavailable", "message" => message}} = json_response(conn, 410)
    assert message =~ "missing"
  end

  test "Given journey log, when GET /e2e/runs/:id/results/:journey_id/log, then log content is returned", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1"
      })

    {:ok, log_ref} = LogStore.write_log(run.id, 1, "auth", "{\"status\":\"ok\"}\n")

    assert {:ok, _} =
             E2E.submit_results(run.id, [
               %{
                 journey_id: "auth",
                 status: "passed",
                 duration_ms: 1200,
                 log_ref: log_ref
               }
             ])

    conn = get(conn, ~p"/e2e/runs/#{run.id}/results/auth/log")

    assert %{"data" => %{"run_id" => _, "journey_id" => "auth", "content" => content}} = json_response(conn, 200)
    assert content =~ "{\"status\":\"ok\"}"
  end

  test "Given a result database error, when POST results, then internal details are not exposed", %{conn: conn} do
    Application.put_env(:nixstasis, :e2e_context, __MODULE__.SubmitErrorContext)

    payload = %{
      "results" => [
        %{
          "journey_id" => "auth",
          "status" => "passed",
          "duration_ms" => 1200
        }
      ]
    }

    conn = post(conn, ~p"/e2e/runs/run-123/results", payload)

    assert %{"error" => %{"code" => "database_error", "message" => "Failed to update results."} = error} =
             response = json_response(conn, 422)

    refute Map.has_key?(error, "details")
    refute inspect(response) =~ "not_null_violation"
  end

  defmodule SubmitErrorContext do
    def submit_results(_run_id, _results), do: {:error, {:database_error, {:not_null_violation, :status}}}
  end
end
