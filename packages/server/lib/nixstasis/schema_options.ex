defmodule Nixstasis.SchemaOptions do
  @moduledoc """
  Loads and validates schema-driven dropdown options for builders.
  """

  alias Nixstasis.Devices
  alias Nixstasis.SchemaOptions.Normalizer
  alias Nixstasis.SchemaOptions.Validator

  def list_schema_references do
    Devices.list_schema_references()
  end

  def options_for(schema_id, schema_version, builder)
      when is_binary(schema_id) and is_binary(schema_version) and schema_id != "" do
    with schema when is_map(schema) and map_size(schema) > 0 <-
           Devices.get_schema_definition(schema_id, schema_version),
         options <- Normalizer.normalize(schema) do
      {:ok,
       %{
         schema_id: schema_id,
         schema_version: schema_version,
         builder: normalize_builder(builder),
         options: options
       }}
    else
      true -> {:error, :not_found}
      _ -> {:error, :not_found}
    end
  end

  def options_for(_, _, _), do: {:error, :invalid}

  def validate_selections(builder, schema_id, schema_version, selections)
      when is_list(selections) do
    case options_for(schema_id, schema_version, builder) do
      {:ok, %{options: options}} ->
        Validator.validate(selections, options)

      {:error, :not_found} ->
        %{
          valid: false,
          issues: [
            %{
              issue_code: "schema_unavailable",
              message: "Schema options are unavailable",
              slot_id: nil,
              blocking: true
            }
          ],
          cleared_slot_ids: []
        }

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

  defp normalize_builder(builder) when builder in ["alert", :alert], do: "alert"
  defp normalize_builder(builder) when builder in ["report", :report], do: "report"
  defp normalize_builder(_), do: "alert"
end
