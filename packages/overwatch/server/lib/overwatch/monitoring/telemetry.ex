defmodule Nixstasis.Monitoring.Telemetry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "telemetry_events" do
    field(:timestamp, :utc_datetime)
    field(:payload, :map, default: %{})

    belongs_to(:device, Nixstasis.Devices.Device)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(telemetry, attrs) do
    telemetry
    |> cast(attrs, [:device_id, :timestamp, :payload])
    |> validate_required([:device_id, :timestamp, :payload])
  end
end
