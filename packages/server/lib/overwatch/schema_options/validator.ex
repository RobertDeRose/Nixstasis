defmodule Nixstasis.SchemaOptions.Validator do
  @moduledoc """
  Validates builder selections against available schema options.
  """

  @invalid_field_code "invalid_schema_field"

  def validate(selections, options) when is_list(selections) and is_list(options) do
    valid_keys = MapSet.new(Enum.map(options, & &1.key))

    issues =
      selections
      |> Enum.flat_map(fn selection ->
        slot_id = Map.get(selection, "slot_id") || Map.get(selection, :slot_id)
        selected_key = Map.get(selection, "selected_key") || Map.get(selection, :selected_key)

        cond do
          is_nil(selected_key) or selected_key == "" ->
            []

          MapSet.member?(valid_keys, selected_key) ->
            []

          true ->
            [
              %{
                issue_code: @invalid_field_code,
                message: "Selection is not valid for active schema",
                slot_id: slot_id,
                blocking: true
              }
            ]
        end
      end)

    %{
      valid: Enum.empty?(issues),
      issues: issues,
      cleared_slot_ids:
        issues
        |> Enum.map(& &1.slot_id)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  def validate(_, _), do: %{valid: false, issues: [], cleared_slot_ids: []}
end
