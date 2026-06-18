defimpl AshJsonApi.ToJsonApiError, for: Nixstasis.SchemaOptions.BuilderContract.OptionsNotFound do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 404,
      code: "not_found",
      title: "Schema Options Not Found",
      detail: Exception.message(error),
      meta: %{schema_id: error.schema_id, schema_version: error.schema_version}
    }
  end
end

defimpl AshJsonApi.ToJsonApiError, for: Nixstasis.SchemaOptions.BuilderContract.OptionsInvalid do
  def to_json_api_error(error) do
    %AshJsonApi.Error{
      id: Ash.UUID.generate(),
      status_code: 422,
      code: "invalid",
      title: "Invalid Schema Options Request",
      detail: Exception.message(error),
      meta: %{builder: error.builder}
    }
  end
end
