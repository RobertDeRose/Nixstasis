defmodule Nixstasis.SchemaOptions.BuilderContract do
  @moduledoc """
  Ash action resource for schema-driven builder API contracts.
  """

  use Ash.Resource,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  alias Nixstasis.SchemaOptions

  @schema_reference_fields [
    schema_id: [type: :string, allow_nil?: false],
    schema_version: [type: :string, allow_nil?: false],
    product_name: [type: :string, allow_nil?: false],
    readable: [type: :boolean, allow_nil?: false]
  ]

  @option_fields [
    key: [type: :string, allow_nil?: false],
    label: [type: :string, allow_nil?: false],
    value_type: [type: :string, allow_nil?: false],
    order_index: [type: :integer, allow_nil?: false],
    selectable: [type: :boolean, allow_nil?: false]
  ]

  @options_payload_fields [
    schema_id: [type: :string, allow_nil?: false],
    schema_version: [type: :string, allow_nil?: false],
    builder: [type: :string, allow_nil?: false],
    options: [type: {:array, :map}, allow_nil?: false, constraints: [items: [fields: @option_fields]]]
  ]

  @options_result_fields [
    status: [type: :atom, allow_nil?: false, constraints: [one_of: [:ok, :error]]],
    reason: [type: :atom, constraints: [one_of: [:not_found, :invalid]]],
    payload: [type: :map, constraints: [fields: @options_payload_fields]]
  ]

  @issue_fields [
    issue_code: [type: :string, allow_nil?: false],
    message: [type: :string, allow_nil?: false],
    slot_id: [type: :string],
    blocking: [type: :boolean, allow_nil?: false]
  ]

  @validation_result_fields [
    valid: [type: :boolean, allow_nil?: false],
    issues: [type: {:array, :map}, allow_nil?: false, constraints: [items: [fields: @issue_fields]]],
    cleared_slot_ids: [type: {:array, :string}, allow_nil?: false]
  ]

  @selection_fields [
    slot_id: [type: :string],
    selected_key: [type: :string]
  ]

  json_api do
    type "builder_contract"
  end

  actions do
    action :list_schema_references, {:array, :map} do
      constraints items: [fields: @schema_reference_fields]

      run fn _input, _context ->
        {:ok, SchemaOptions.list_schema_references()}
      end
    end

    action :options_for, :map do
      constraints fields: @options_result_fields

      argument :schema_id, :string, allow_nil?: false
      argument :schema_version, :string, allow_nil?: false
      argument :builder, :string, default: "alert", allow_nil?: false

      run fn input, _context ->
        case SchemaOptions.options_for(
               input.arguments.schema_id,
               input.arguments.schema_version,
               input.arguments.builder
             ) do
          {:ok, payload} -> {:ok, %{status: :ok, payload: payload}}
          {:error, reason} -> {:ok, %{status: :error, reason: reason}}
        end
      end
    end

    action :validate_builder_configuration, :map do
      constraints fields: @validation_result_fields

      argument :builder, :string
      argument :schema_id, :string
      argument :schema_version, :string

      argument :selections, {:array, :map},
        constraints: [items: [fields: @selection_fields]],
        default: [],
        allow_nil?: false

      run fn input, _context ->
        {:ok,
         SchemaOptions.validate_selections(
           input.arguments.builder,
           input.arguments.schema_id,
           input.arguments.schema_version,
           input.arguments.selections
         )}
      end
    end
  end
end
