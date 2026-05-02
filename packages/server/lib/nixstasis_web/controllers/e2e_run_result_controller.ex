defmodule NixstasisWeb.E2ERunResultController do
  use NixstasisWeb, :controller

  alias Nixstasis.E2E

  def index(conn, %{"id" => run_id}) do
    case E2E.get_run(run_id) do
      {:ok, _run} ->
        results = E2E.list_results(run_id)
        render(conn, :index, results: results)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "")
    end
  end

  def create(conn, %{"id" => run_id, "results" => results}) when is_list(results) do
    case E2E.submit_results(run_id, results) do
      {:ok, %{results: updated_results}} ->
        conn
        |> put_status(:accepted)
        |> render(:index, results: updated_results)

      {:error, :not_found} ->
        send_resp(conn, :not_found, "")

      {:error, {:invalid, message}} ->
        conn
        |> put_status(:bad_request)
        |> json(error_payload("invalid_request", message))

      {:error, {:database_error, reason}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("database_error", "Failed to update results", inspect(reason)))
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(error_payload("invalid_request", "Results payload is required."))
  end

  def log(conn, %{"id" => run_id, "journey_id" => journey_id}) do
    case E2E.fetch_result_log(run_id, journey_id) do
      {:ok, content} ->
        json(conn, %{data: %{run_id: run_id, journey_id: journey_id, content: content}})

      {:error, :not_found} ->
        send_resp(conn, :not_found, "")

      {:error, {:log_unavailable, message}} ->
        conn
        |> put_status(:gone)
        |> json(error_payload("log_unavailable", message))
    end
  end

  defp error_payload(code, message, details \\ nil) do
    payload = %{error: %{code: code, message: message}}
    if details, do: put_in(payload, [:error, :details], details), else: payload
  end
end
