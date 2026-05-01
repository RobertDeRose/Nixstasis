defmodule Nixstasis.SchemaOptions do
  @moduledoc """
  Loads and validates schema-driven dropdown options for builders.
  """

  alias Nixstasis.Devices
  alias Nixstasis.SchemaOptions.Normalizer
  alias Nixstasis.SchemaOptions.Validator

  @default_version "v1"

  def list_schema_references do
    Devices.list_devices()
    |> Enum.reduce(%{}, fn device, acc ->
      schema = device.schema || %{}
      schema_id = device.product_name
      schema_version = schema_version(schema)

      if is_binary(schema_id) and schema_id != "" and is_map(schema) and map_size(schema) > 0 do
        key = {schema_id, schema_version}

        Map.put_new(acc, key, %{
          schema_id: schema_id,
          schema_version: schema_version,
          product_name: schema_id,
          readable: true
        })
      else
        acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.schema_id, &1.schema_version})
  end

  def options_for(schema_id, schema_version, builder)
      when is_binary(schema_id) and is_binary(schema_version) and schema_id != "" do
    devices =
      Devices.list_devices()
      |> Enum.filter(fn device ->
        device.product_name == schema_id and schema_version(device.schema || %{}) == schema_version
      end)

    with false <- Enum.empty?(devices),
         schema when is_map(schema) <- schema_from_devices(devices),
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

  defp schema_from_devices(devices) do
    devices
    |> Enum.map(&(&1.schema || %{}))
    |> Enum.find(%{}, fn schema -> is_map(schema) and map_size(schema) > 0 end)
  end

  defp schema_version(schema) when is_map(schema) do
    version = schema["version"] || schema[:version]
    if is_binary(version) and version != "", do: version, else: @default_version
  end

  defp schema_version(_), do: @default_version

  defp normalize_builder(builder) when builder in ["alert", :alert], do: "alert"
  defp normalize_builder(builder) when builder in ["report", :report], do: "report"
  defp normalize_builder(_), do: "alert"
end
