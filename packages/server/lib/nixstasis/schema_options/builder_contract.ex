defmodule Nixstasis.SchemaOptions.BuilderContract do
  @moduledoc """
  Ash action resource for schema-driven builder API contracts.
  """

  use Ash.Resource,
    domain: Nixstasis.Domain,
    extensions: [AshJsonApi.Resource]

  alias Nixstasis.SchemaOptions
  alias Nixstasis.Types.BuilderKind

  defmodule OptionsNotFound do
    @moduledoc false

    use Splode.Error, class: :invalid, fields: [:schema_id, :schema_version, :builder]

    def message(error) do
      "schema options not found for #{error.schema_id} #{error.schema_version}"
    end
  end

  defmodule OptionsInvalid do
    @moduledoc false

    use Splode.Error, class: :invalid, fields: [:builder]

    def message(error), do: "invalid schema options request for #{error.builder} builder"
  end

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
    builder: [type: BuilderKind, allow_nil?: false],
    load_time_ms: [type: :integer, allow_nil?: false, constraints: [min: 0]],
    options: [type: {:array, :map}, allow_nil?: false, constraints: [items: [fields: @option_fields]]]
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
    slot_id: [type: :string, allow_nil?: false],
    selected_key: [type: :string, allow_nil?: false]
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
      constraints fields: @options_payload_fields

      argument :schema_id, :string, allow_nil?: false
      argument :schema_version, :string, allow_nil?: false

      argument :builder, BuilderKind, default: :alert

      run fn input, _context ->
        case SchemaOptions.options_for(
               input.arguments.schema_id,
               input.arguments.schema_version,
               to_string(input.arguments.builder)
             ) do
          {:ok, payload} -> {:ok, payload}
          {:error, :not_found} -> {:error, OptionsNotFound.exception(Map.to_list(input.arguments))}
          {:error, :invalid} -> {:error, OptionsInvalid.exception(builder: to_string(input.arguments.builder))}
        end
      end
    end

    action :validate_builder_configuration, :map do
      constraints fields: @validation_result_fields

      argument :builder, BuilderKind, allow_nil?: false
      argument :schema_id, :string, allow_nil?: false
      argument :schema_version, :string, allow_nil?: false

      argument :selections, {:array, :map},
        constraints: [items: [fields: @selection_fields]],
        allow_nil?: false

      run fn input, _context ->
        {:ok,
         SchemaOptions.validate_selections(
           to_string(input.arguments.builder),
           input.arguments.schema_id,
           input.arguments.schema_version,
           input.arguments.selections
         )}
      end
    end
  end
end
