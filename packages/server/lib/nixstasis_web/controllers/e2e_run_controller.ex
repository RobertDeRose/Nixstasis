defmodule NixstasisWeb.E2ERunController do
  use NixstasisWeb, :controller

  alias Nixstasis.E2E
  alias Nixstasis.E2E.Run

  @protocol_header "x-e2e-protocol-version"

  def index(conn, _params) do
    runs = E2E.list_runs()
    render(conn, :index, runs: runs)
  end

  def suites(conn, _params) do
    suites = E2E.list_suites()
    render(conn, :suites, suites: suites)
  end

  def create(conn, params) do
    protocol_version =
      conn
      |> get_req_header(@protocol_header)
      |> List.first()

    params = Map.put(params, "protocol_version", protocol_version)

    case E2E.create_run(params) do
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
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("database_error", "Failed to create run", inspect(reason)))
    end
  end

  def show(conn, %{"id" => id}) do
    case E2E.get_run(id) do
      {:ok, run} -> render(conn, :show, run: run)
      {:error, :not_found} -> send_resp(conn, :not_found, "")
    end
  end

  def cancel(conn, %{"id" => id}) do
    case E2E.cancel_run(id) do
      {:ok, run} ->
        conn
        |> put_status(:accepted)
        |> render(:show, run: run)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("database_error", "Failed to cancel run", inspect(changeset)))
    end
  end

  defp error_payload(code, message, details \\ nil) do
    payload = %{error: %{code: code, message: message}}
    if details, do: put_in(payload, [:error, :details], details), else: payload
  end
end
