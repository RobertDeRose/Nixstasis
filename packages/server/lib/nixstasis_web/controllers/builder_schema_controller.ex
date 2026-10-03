defmodule NixstasisWeb.BuilderSchemaController do
  use NixstasisWeb, :controller

  alias Nixstasis.Domain

  def index(conn, _params) do
    refs = Domain.list_builder_schema_references!()
    render(conn, :index, refs: refs)
  end

  def options(conn, %{"schema_id" => schema_id, "schema_version" => schema_version} = params) do
    builder = Map.get(params, "builder", "alert")
    started_at = System.monotonic_time(:millisecond)

    case Domain.get_builder_schema_options(schema_id, schema_version, builder) do
      {:ok, payload} ->
        load_time_ms = max(System.monotonic_time(:millisecond) - started_at, 0)

        render(conn, :options, payload: %{payload | load_time_ms: load_time_ms})

      {:error, %Ash.Error.Invalid{errors: [%Nixstasis.SchemaOptions.BuilderContract.OptionsNotFound{} | _]}} ->
        conn
        |> put_status(:not_found)
        |> json(error_payload("schema_not_found", "Schema reference not found"))

      {:error, %Ash.Error.Invalid{errors: [%Nixstasis.SchemaOptions.BuilderContract.OptionsConflict{} | _]}} ->
        conn
        |> put_status(:conflict)
        |> json(error_payload("schema_conflict", "Schema definitions conflict for this product/version"))

      {:error, _error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("invalid_request", "Invalid schema options request"))
    end
  end

  defp error_payload(code, message) do
    %{error: %{code: code, message: message}}
  end
end
