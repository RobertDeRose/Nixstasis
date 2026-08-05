defmodule Nixstasis.SchemaOptions do
  @moduledoc """
  Loads and validates schema-driven dropdown options for builders.
  """

  alias Nixstasis.Devices
  alias Nixstasis.SchemaOptions.Normalizer
  alias Nixstasis.SchemaOptions.Validator

  @schema_options_load_event [:nixstasis, :builder, :schema_options, :load]

  def list_schema_references do
    Devices.list_schema_references()
  end

  def options_for(schema_id, schema_version, builder)
      when is_binary(schema_id) and is_binary(schema_version) and schema_id != "" do
    started_at = System.monotonic_time(:microsecond)
    result = options_for_result(schema_id, schema_version, builder)
    duration_us = max(System.monotonic_time(:microsecond) - started_at, 0)

    :telemetry.execute(
      @schema_options_load_event,
      %{duration_ms: div(duration_us, 1_000)},
      %{
        builder: builder_metadata(builder),
        schema_id: schema_id,
        schema_version: schema_version,
        result: result_status(result)
      }
    )

    result
  end

  def options_for(_, _, _), do: {:error, :invalid}

  defp options_for_result(schema_id, schema_version, builder) do
    with {:ok, normalized_builder} <- normalize_builder(builder),
         {:ok, schema} <- Devices.get_schema_definition(schema_id, schema_version),
         options <- Normalizer.normalize(schema) do
      {:ok,
       %{
         schema_id: schema_id,
         schema_version: schema_version,
         builder: normalized_builder,
         load_time_ms: 0,
         options: options
       }}
    else
      {:error, :invalid} -> {:error, :invalid}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :conflict} -> {:error, :conflict}
    end
  end

  def validate_selections(builder, schema_id, schema_version, selections)
      when is_list(selections) do
    case options_for(schema_id, schema_version, builder) do
      {:ok, %{options: options}} ->
        Validator.validate(selections, options)

      {:error, :not_found} ->
        schema_unavailable_result("schema_unavailable", "Schema options are unavailable")

      {:error, :conflict} ->
        schema_unavailable_result(
          "schema_conflict",
          "Schema definitions conflict for this product/version."
        )

      _ ->
        %{
          valid: false,
          issues: [
            %{
              issue_code: "schema_access_lost",
              message: "Schema access is unavailable",
              slot_id: nil,
              blocking: true
            }
          ],
          cleared_slot_ids: []
        }
    end
  end

  def validate_selections(_builder, _schema_id, _schema_version, _selections) do
    %{valid: false, issues: [], cleared_slot_ids: []}
  end

  def schema_issue_message(:conflict), do: "Schema definitions conflict for this product/version."
  def schema_issue_message(:not_found), do: "Schema options are unavailable."
  def schema_issue_message(_), do: "Schema access is unavailable."

  defp builder_metadata(builder) when builder in ["alert", :alert], do: "alert"
  defp builder_metadata(builder) when builder in ["report", :report], do: "report"
  defp builder_metadata(_), do: "unknown"

  defp result_status({:ok, _}), do: :ok
  defp result_status({:error, reason}), do: reason

  defp schema_unavailable_result(issue_code, message) do
    %{
      valid: false,
      issues: [
        %{
          issue_code: issue_code,
          message: message,
          slot_id: nil,
          blocking: true
        }
      ],
      cleared_slot_ids: []
    }
  end

  defp normalize_builder(builder) when builder in ["alert", :alert], do: {:ok, "alert"}
  defp normalize_builder(builder) when builder in ["report", :report], do: {:ok, "report"}
  defp normalize_builder(_), do: {:error, :invalid}
end
