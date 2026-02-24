defmodule NixstasisWeb.BuilderSchemaJSON do
  def index(%{refs: refs}) do
    %{
      data:
        Enum.map(refs, fn ref ->
          %{
            schema_id: ref.schema_id,
            schema_version: ref.schema_version,
            product_name: ref.product_name,
            readable: ref.readable
          }
        end)
    }
  end

  def options(%{payload: payload}) do
    %{
      data: %{
        schema_id: payload.schema_id,
        schema_version: payload.schema_version,
        builder: payload.builder,
        load_time_ms: payload.load_time_ms,
        options:
          Enum.map(payload.options, fn option ->
            %{
              key: option.key,
              label: option.label,
              value_type: option.value_type,
              order_index: option.order_index,
              selectable: option.selectable
            }
          end)
      }
    }
  end
end
