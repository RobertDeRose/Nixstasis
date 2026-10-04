defmodule Nixstasis.Monitoring.Validations.TelemetryPayload do
  @moduledoc """
  Enforces telemetry persistence limits on direct Ash writes.
  """

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias Nixstasis.Monitoring.TelemetryLimits

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def supports(_opts), do: [Ash.Changeset, Ash.ActionInput]

  @impl true
  def validate(changeset, _opts, _context) do
    payload = Ash.Changeset.get_attribute(changeset, :payload)

    case TelemetryLimits.validate(payload) do
      :ok ->
        :ok

      {:error, message} ->
        {:error, InvalidAttribute.exception(field: :payload, message: message, value: payload)}
    end
  end
end
