defmodule NixstasisWeb.ProvisioningController do
  use NixstasisWeb, :controller

  alias Nixstasis.Provisioning
  alias NixstasisWeb.OperatorContext

  require Logger

  @read_chunk_size 64 * 1024
  @max_artifact_size 32 * 1024 * 1024

  def create(conn, %{"device_id" => device_id}) do
    with :ok <- require_artifact_content_type(conn),
         {:ok, session} <- operator_session(conn),
         {:ok, artifact} <- read_artifact(conn),
         {:ok, delivery} <-
           Provisioning.deliver(session, device_id, artifact,
             filename: config_filename(conn),
             attempt_id: attempt_id(conn)
           ) do
      render_delivery(conn, delivery)
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def show(conn, %{"id" => delivery_id}) do
    with {:ok, session} <- operator_session(conn),
         {:ok, delivery} <- Provisioning.get_delivery(session, delivery_id) do
      render_delivery(conn, delivery)
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def withdraw(conn, %{"id" => delivery_id}) do
    with {:ok, session} <- operator_session(conn),
         :ok <- Provisioning.withdraw_delivery(session, delivery_id) do
      json(conn, %{data: %{id: delivery_id, withdrawn: true}})
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp require_artifact_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [content_type | _] when content_type == "application/octet-stream" -> :ok
      _ -> {:error, :unsupported_content_type}
    end
  end

  defp operator_session(conn) do
    case OperatorContext.from_conn(conn) do
      {:ok, context} ->
        {:ok, session_from_context(context)}

      :local_development ->
        permissions = OperatorContext.local_development_permissions()

        {:ok,
         Map.put(permissions, "operator_context", %{
           "subject" => "local-development"
         })}

      :error ->
        {:error, :unauthorized}
    end
  end

  defp session_from_context(context) do
    context
    |> Map.take([
      "device_permissions",
      "report_permissions",
      "script_permissions",
      "command_policy_permissions"
    ])
    |> Map.put("operator_context", context)
  end

  defp read_artifact(conn), do: read_artifact(conn, [], 0)

  defp read_artifact(conn, chunks, total) do
    case Plug.Conn.read_body(conn, length: @read_chunk_size) do
      {:ok, chunk, _conn} ->
        size = total + byte_size(chunk)

        if size > @max_artifact_size do
          {:error, :artifact_too_large}
        else
          {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks]))}
        end

      {:more, chunk, next_conn} ->
        new_total = total + byte_size(chunk)

        if new_total > @max_artifact_size do
          {:error, :artifact_too_large}
        else
          read_artifact(next_conn, [chunk | chunks], new_total)
        end

      {:error, reason} ->
        {:error, {:body_read_failed, reason}}
    end
  end

  defp config_filename(conn), do: get_req_header(conn, "x-config-filename") |> List.first() || "config.toml"
  defp attempt_id(conn), do: get_req_header(conn, "x-nixstasis-bootstrap-attempt-id") |> List.first()

  defp render_delivery(conn, delivery) do
    status =
      case delivery.state do
        :succeeded -> :ok
        :failed -> :unprocessable_entity
        :indeterminate -> :service_unavailable
        _state -> :accepted
      end

    conn
    |> put_status(status)
    |> json(%{data: Provisioning.data(delivery)})
  end

  defp render_error(conn, :unauthorized), do: error(conn, :unauthorized, "operator authorization is required", 401)
  defp render_error(conn, :not_found), do: error(conn, :not_found, "device or delivery not found", 404)
  defp render_error(conn, :device_not_approved), do: error(conn, :device_not_approved, "device is not approved", 422)
  defp render_error(conn, :device_offline), do: error(conn, :device_offline, "device is offline", 422)

  defp render_error(conn, :unsupported_content_type),
    do: error(conn, :unsupported_content_type, "content-type must be application/octet-stream", 415)

  defp render_error(conn, :artifact_too_large),
    do: error(conn, :artifact_too_large, "artifact exceeds the bounded upload limit", 413)

  defp render_error(conn, :empty_artifact), do: error(conn, :empty_artifact, "artifact must not be empty", 422)
  defp render_error(conn, :invalid_artifact), do: error(conn, :invalid_artifact, "artifact must be binary", 422)

  defp render_error(conn, :unsupported_filename),
    do: error(conn, :unsupported_filename, "artifact filename is not supported", 422)

  defp render_error(conn, :invalid_attempt_id),
    do: error(conn, :invalid_attempt_id, "bootstrap attempt id must be a UUID", 422)

  defp render_error(conn, :new_attempt_required),
    do: error(conn, :new_attempt_required, "an explicit new attempt id is required", 409)

  defp render_error(conn, {:reconciliation_required, delivery}),
    do:
      conn
      |> put_status(:conflict)
      |> json(%{error: %{code: "reconciliation_required", delivery: Provisioning.data(delivery)}})

  defp render_error(conn, {:existing_delivery, delivery}),
    do:
      conn
      |> put_status(:conflict)
      |> json(%{error: %{code: "existing_delivery", delivery: Provisioning.data(delivery)}})

  defp render_error(conn, {:body_read_failed, reason}),
    do: error(conn, :body_read_failed, "could not read artifact: #{inspect(reason)}", 400)

  defp render_error(conn, {:error, reason}), do: render_error(conn, reason)

  defp render_error(conn, reason) do
    Logger.warning("provisioning request failed", reason: inspect(reason))
    error(conn, :provisioning_failed, "provisioning request could not be completed", 422)
  end

  defp error(conn, code, message, status) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end
end
