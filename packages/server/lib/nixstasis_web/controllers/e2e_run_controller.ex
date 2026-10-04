defmodule NixstasisWeb.E2ERunController do
  use NixstasisWeb, :controller

  require Logger

  alias Nixstasis.E2E
  alias Nixstasis.E2E.Run

  @protocol_header "x-e2e-protocol-version"
  @max_list_limit 100

  def index(conn, params) do
    runs = e2e_context().list_runs_for_runner(runner_id(conn), limit: list_limit(params))
    render(conn, :index, runs: runs)
  end

  def suites(conn, _params) do
    suites = e2e_context().list_suites()
    render(conn, :suites, suites: suites)
  end

  def create(conn, params) do
    protocol_version =
      conn
      |> get_req_header(@protocol_header)
      |> List.first()

    params =
      params
      |> Map.put("protocol_version", protocol_version)
      |> Map.put("runner_id", runner_id(conn))

    case e2e_context().create_run(params) do
      {:ok, %Run{} = run} ->
        conn
        |> put_status(:created)
        |> render(:show, run: run)

      {:error, {:environment_locked, message}} ->
        conn
        |> put_status(:conflict)
        |> json(error_payload("environment_locked", message))

      {:error, {:protocol_mismatch, message}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("protocol_mismatch", message))

      {:error, {:invalid_action_expectation, message}} ->
        conn
        |> put_status(:bad_request)
        |> json(error_payload("invalid_action_expectation", message))

      {:error, {:seed_failed, message}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("seed_failed", message))

      {:error, {:invalid, message}} ->
        conn
        |> put_status(:bad_request)
        |> json(error_payload("invalid_request", message))

      {:error, {:database_error, reason}} ->
        Logger.error("Failed to create E2E run: #{inspect(reason)}")

        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("database_error", "Failed to create run."))
    end
  end

  def show(conn, %{"id" => id}) do
    case e2e_context().get_run_for_runner(id, runner_id(conn)) do
      {:ok, run} -> render(conn, :show, run: run)
      {:error, :not_found} -> send_resp(conn, :not_found, "")
    end
  end

  def cancel(conn, %{"id" => id}) do
    with {:ok, _run} <- e2e_context().get_run_for_runner(id, runner_id(conn)) do
      case e2e_context().cancel_run(id) do
        {:ok, run} ->
          conn
          |> put_status(:accepted)
          |> render(:show, run: run)

        {:error, :not_found} ->
          send_resp(conn, :not_found, "")

        {:error, changeset} ->
          Logger.error("Failed to cancel E2E run #{id}: #{inspect(changeset)}")

          conn
          |> put_status(:unprocessable_entity)
          |> json(error_payload("database_error", "Failed to cancel run."))
      end
    else
      {:error, :not_found} -> send_resp(conn, :not_found, "")
    end
  end

  defp list_limit(params) do
    case Integer.parse(to_string(Map.get(params, "limit", "100"))) do
      {limit, ""} when limit > 0 -> min(limit, @max_list_limit)
      _ -> @max_list_limit
    end
  end

  defp runner_id(conn), do: conn.assigns.e2e_runner_id
  defp error_payload(code, message), do: %{error: %{code: code, message: message}}
  defp e2e_context, do: Application.get_env(:nixstasis, :e2e_context, E2E)
end
