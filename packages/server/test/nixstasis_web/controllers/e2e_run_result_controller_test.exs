defmodule NixstasisWeb.E2ERunResultControllerTest do
  use NixstasisWeb.ConnCase

  import ExUnit.CaptureLog

  alias Nixstasis.E2E
  alias Nixstasis.E2E.LogStore

  @runner_id "test-runner"
  @runner_token "test-e2e-runner-token-0123456789abcdef0123456789abcdef"
  @other_runner_id "other-runner"
  @other_runner_token "other-e2e-runner-token-0123456789abcdef0123456789abcdef"

  setup %{conn: conn} do
    previous = Application.get_env(:nixstasis, :e2e)
    previous_context = Application.get_env(:nixstasis, :e2e_context)

    Application.put_env(:nixstasis, :e2e,
      allowed_env_labels: ["local"],
      environments: %{"local" => %{seed_script: "e2e/seed.exs"}},
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

    {:ok, conn: e2e_auth(conn)}
  end

  defp e2e_auth(conn, runner_id \\ @runner_id, token \\ @runner_token) do
    conn
    |> put_req_header("x-e2e-runner-id", runner_id)
    |> put_req_header("authorization", "Bearer " <> token)
  end

  test "Given a run, when GET /e2e/runs/:id/results, then results are returned", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
      })

    conn = get(conn, ~p"/e2e/runs/#{run.id}/results")

    assert %{"data" => results} = json_response(conn, 200)
    assert length(results) == 1
    assert hd(results)["journey_id"] == "auth"
  end

  test "Given another runner's run, when results or logs are accessed, then they are hidden" do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
      })

    payload = %{
      "results" => [%{"journey_id" => "auth", "status" => "passed", "duration_ms" => 1}]
    }

    other_conn = e2e_auth(build_conn(), @other_runner_id, @other_runner_token)
    assert response(get(other_conn, ~p"/e2e/runs/#{run.id}/results"), 404)

    other_conn = e2e_auth(build_conn(), @other_runner_id, @other_runner_token)
    assert response(post(other_conn, ~p"/e2e/runs/#{run.id}/results", payload), 404)

    other_conn = e2e_auth(build_conn(), @other_runner_id, @other_runner_token)
    assert response(get(other_conn, ~p"/e2e/runs/#{run.id}/results/auth/log"), 404)

    assert {:ok, unchanged} = E2E.get_run(run.id)
    assert unchanged.status == "queued"
  end

  test "Given results payload, when POST /e2e/runs/:id/results, then results are stored", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
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
        protocol_version: "1",
        runner_id: @runner_id
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
        protocol_version: "1",
        runner_id: @runner_id
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

    {conn, log} = with_log(fn -> post(conn, ~p"/e2e/runs/run-123/results", payload) end)

    assert log =~ "Failed to update E2E results for run run-123"

    assert %{"error" => %{"code" => "database_error", "message" => "Failed to update results."} = error} =
             response = json_response(conn, 422)

    refute Map.has_key?(error, "details")
    refute inspect(response) =~ "not_null_violation"
  end

  defmodule SubmitErrorContext do
    def get_run_for_runner(_id, _runner_id), do: {:ok, %Nixstasis.E2E.Run{id: Ecto.UUID.generate()}}
    def submit_results(_run_id, _results), do: {:error, {:database_error, {:not_null_violation, :status}}}
  end
end
