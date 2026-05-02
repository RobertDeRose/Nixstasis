defmodule NixstasisWeb.BuilderSchemaController do
  use NixstasisWeb, :controller

  alias Nixstasis.SchemaOptions

  def index(conn, _params) do
    refs = SchemaOptions.list_schema_references()
    render(conn, :index, refs: refs)
  end

  def options(conn, %{"schema_id" => schema_id, "schema_version" => schema_version} = params) do
    builder = Map.get(params, "builder", "alert")

    case SchemaOptions.options_for(schema_id, schema_version, builder) do
      {:ok, payload} ->
        load_time_ms =
          System.monotonic_time(:millisecond)
          |> rem(10)

        render(conn, :options, payload: Map.put(payload, :load_time_ms, load_time_ms))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(error_payload("schema_not_found", "Schema reference not found"))

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(error_payload("invalid_request", "Invalid schema options request"))
    end
  end

  defp error_payload(code, message) do
    %{error: %{code: code, message: message}}
  end
end
