defmodule Nixstasis.Devices.Validations.SchemaDefinition do
  @moduledoc """
  Validates device schema definitions using the app-level validator.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias Nixstasis.Devices.SchemaValidator

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def supports(_opts), do: [Ash.Changeset, Ash.ActionInput]

  @impl true
  def validate(changeset, _opts, _context) do
    schema = Ash.Changeset.get_attribute(changeset, :schema) || %{}

    case SchemaValidator.validate(schema) do
      :ok ->
        :ok

      {:error, message} ->
        {:error, InvalidAttribute.exception(field: :schema, message: message, value: schema)}
    end
  end
end
