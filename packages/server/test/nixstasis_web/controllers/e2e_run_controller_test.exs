defmodule NixstasisWeb.E2ERunControllerTest do
  use NixstasisWeb.ConnCase

  import ExUnit.CaptureLog

  alias Nixstasis.E2E

  @runner_id "test-runner"
  @runner_token "test-e2e-runner-token-0123456789abcdef0123456789abcdef"
  @other_runner_id "other-runner"
  @other_runner_token "other-e2e-runner-token-0123456789abcdef0123456789abcdef"

  setup %{conn: conn} do
    previous = Application.get_env(:nixstasis, :e2e)
    previous_context = Application.get_env(:nixstasis, :e2e_context)

    Application.put_env(:nixstasis, :e2e,
      allowed_env_labels: ["local"],
      environments: %{
        "local" => %{seed_script: "e2e/seed.exs"}
      },
      suites: %{"full" => ["auth", "dashboard"], "runtime" => ["runtime_linux_telemetry"]},
      protocol_versions: ["1"]
    )

    on_exit(fn ->
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

  defp create_headers(conn) do
    conn
    |> e2e_auth()
    |> put_req_header("x-e2e-protocol-version", "1")
  end

  defp e2e_auth(conn, runner_id \\ @runner_id, token \\ @runner_token) do
    conn
    |> put_req_header("x-e2e-runner-id", runner_id)
    |> put_req_header("authorization", "Bearer " <> token)
  end

  test "Given valid run params, when POST /e2e/runs, then a run is created", %{conn: conn} do
    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual"
    }

    conn = conn |> create_headers() |> post(~p"/e2e/runs", params)

    assert %{"data" => data} = json_response(conn, 201)
    assert data["id"]
    assert data["suite_id"] == "full"
    assert data["status"] == "queued"
    assert data["protocol_version"] == "1"

    assert {:ok, stored} = E2E.get_run(data["id"])
    assert stored.runner_id == @runner_id
  end

  test "Given no runner credential, when E2E is enabled, then browser roles cannot access the API" do
    conn =
      build_conn()
      |> put_req_header("x-token-user-roles", "nixstasis/admin")
      |> get(~p"/e2e/runs")

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  test "Given an invalid runner token, when E2E is enabled, then the request is rejected" do
    conn =
      build_conn()
      |> e2e_auth(@runner_id, String.duplicate("x", 32))
      |> get(~p"/e2e/runs")

    assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
  end

  test "Given a lowercase bearer scheme, when E2E is enabled, then the runner is authenticated" do
    conn =
      build_conn()
      |> put_req_header("x-e2e-runner-id", @runner_id)
      |> put_req_header("authorization", "bearer " <> @runner_token)
      |> get(~p"/e2e/runs")

    assert %{"data" => _runs} = json_response(conn, 200)
  end

  test "Given a run owned by another runner, when reading or cancelling it, then it is hidden" do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
      })

    other_conn = e2e_auth(build_conn(), @other_runner_id, @other_runner_token)
    assert %{"data" => []} = other_conn |> get(~p"/e2e/runs") |> json_response(200)

    other_conn = e2e_auth(build_conn(), @other_runner_id, @other_runner_token)
    assert response(get(other_conn, ~p"/e2e/runs/#{run.id}"), 404)

    other_conn = e2e_auth(build_conn(), @other_runner_id, @other_runner_token)
    assert response(post(other_conn, ~p"/e2e/runs/#{run.id}/cancel"), 404)

    assert {:ok, unchanged} = E2E.get_run(run.id)
    assert unchanged.status == "queued"
  end

  test "Given existing runs, when GET /e2e/runs, then runs are listed", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
      })

    conn = get(conn, ~p"/e2e/runs")

    assert %{"data" => data} = json_response(conn, 200)
    assert Enum.any?(data, fn item -> item["id"] == run.id end)
  end

  test "Given a nested limit param, when GET /e2e/runs, then the default limit is used", %{conn: conn} do
    conn = get(conn, "/e2e/runs?limit[x]=1")

    assert %{"data" => _runs} = json_response(conn, 200)
  end

  test "Given configured suites, when GET /e2e/suites, then suite catalog is returned", %{conn: conn} do
    conn = get(conn, ~p"/e2e/suites")

    assert %{"data" => suites} = json_response(conn, 200)
    assert Enum.any?(suites, fn suite -> suite["id"] == "full" end)
    assert Enum.any?(suites, fn suite -> suite["id"] == "runtime" end)

    full_suite = Enum.find(suites, fn suite -> suite["id"] == "full" end)
    assert full_suite["journey_ids"] == ["auth", "dashboard"]
  end

  test "Given an existing run, when GET /e2e/runs/:id, then run details are returned", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
      })

    conn = get(conn, ~p"/e2e/runs/#{run.id}")

    assert %{"data" => data} = json_response(conn, 200)
    assert data["id"] == run.id
  end

  test "Given an existing run, when POST /e2e/runs/:id/cancel, then run is cancelled", %{conn: conn} do
    {:ok, run} =
      E2E.create_run(%{
        suite_id: "full",
        environment_label: "local",
        trigger_source: "manual",
        protocol_version: "1",
        runner_id: @runner_id
      })

    conn = post(conn, ~p"/e2e/runs/#{run.id}/cancel")

    assert %{"data" => data} = json_response(conn, 202)
    assert data["status"] == "cancelled"
  end

  test "Given missing preconditions, when POST /e2e/runs, then error is returned", %{conn: conn} do
    params = %{
      "suite_id" => "full",
      "environment_label" => "unknown",
      "trigger_source" => "manual"
    }

    conn = conn |> create_headers() |> post(~p"/e2e/runs", params)

    assert %{"error" => %{"code" => "invalid_request", "message" => message}} = json_response(conn, 400)
    assert message =~ "Environment"
  end

  test "Given missing protocol header, when POST /e2e/runs, then protocol mismatch is returned", %{conn: conn} do
    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual"
    }

    conn = post(conn, ~p"/e2e/runs", params)

    assert %{"error" => %{"code" => "protocol_mismatch", "message" => message}} = json_response(conn, 422)
    assert message =~ "Missing required X-E2E-Protocol-Version"
  end

  test "Given E2E endpoints are disabled, when POST /e2e/runs is requested, then not found is returned", %{
    conn: conn
  } do
    previous = Application.get_env(:nixstasis, :e2e_enabled?)

    Application.put_env(:nixstasis, :e2e_enabled?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :e2e_enabled?, previous) end)

    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual"
    }

    conn = conn |> create_headers() |> post(~p"/e2e/runs", params)

    assert response(conn, 404)
  end

  test "Given legacy version fields, when POST /e2e/runs, then request is rejected", %{conn: conn} do
    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual",
      "client_version" => "1.0.0",
      "server_version" => "1.0.0"
    }

    conn = conn |> create_headers() |> post(~p"/e2e/runs", params)

    assert %{"error" => %{"code" => "protocol_mismatch", "message" => message}} = json_response(conn, 422)
    assert message =~ "Legacy fields client_version/server_version are no longer supported"
  end

  test "Given unsupported protocol header, when POST /e2e/runs, then protocol mismatch is returned", %{conn: conn} do
    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual"
    }

    conn =
      conn
      |> put_req_header("x-e2e-protocol-version", "99")
      |> post(~p"/e2e/runs", params)

    assert %{"error" => %{"code" => "protocol_mismatch", "message" => message}} = json_response(conn, 422)
    assert message =~ "Unsupported protocol version '99'"
  end

  test "Given another active run in same environment, when POST /e2e/runs, then environment lock conflict is returned",
       %{conn: conn} do
    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual"
    }

    assert %{"data" => %{"id" => _id}} =
             conn
             |> create_headers()
             |> post(~p"/e2e/runs", params)
             |> json_response(201)

    conflict_conn = conn |> recycle() |> create_headers() |> post(~p"/e2e/runs", params)

    assert %{"error" => %{"code" => "environment_locked", "message" => message}} = json_response(conflict_conn, 409)
    assert message =~ "already has an active E2E run"
  end

  test "Given a database error, when POST /e2e/runs, then internal details are not exposed", %{conn: conn} do
    Application.put_env(:nixstasis, :e2e_context, __MODULE__.CreateErrorContext)

    params = %{
      "suite_id" => "full",
      "environment_label" => "local",
      "trigger_source" => "manual"
    }

    {conn, log} =
      with_log(fn ->
        conn |> create_headers() |> post(~p"/e2e/runs", params)
      end)

    assert log =~ "Failed to create E2E run"

    assert %{"error" => %{"code" => "database_error", "message" => "Failed to create run."} = error} =
             response = json_response(conn, 422)

    refute Map.has_key?(error, "details")
    refute inspect(response) =~ "not_null_violation"
  end

  test "Given a cancellation database error, when POST cancel, then internal details are not exposed", %{conn: conn} do
    Application.put_env(:nixstasis, :e2e_context, __MODULE__.CancelErrorContext)

    {conn, log} = with_log(fn -> post(conn, ~p"/e2e/runs/run-123/cancel") end)

    assert log =~ "Failed to cancel E2E run run-123"

    assert %{"error" => %{"code" => "database_error", "message" => "Failed to cancel run."} = error} =
             response = json_response(conn, 422)

    refute Map.has_key?(error, "details")
    refute inspect(response) =~ "stale"
  end

  defmodule CreateErrorContext do
    def create_run(_params), do: {:error, {:database_error, {:not_null_violation, :environment_label}}}
  end

  defmodule CancelErrorContext do
    def get_run_for_runner(_id, _runner_id), do: {:ok, %Nixstasis.E2E.Run{id: Ecto.UUID.generate()}}
    def cancel_run(_id), do: {:error, {:stale, :e2e_run}}
  end
end
