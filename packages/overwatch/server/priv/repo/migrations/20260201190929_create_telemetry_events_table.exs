defmodule Nixstasis.Repo.Migrations.CreateTelemetryEventsTable do
  use Ecto.Migration

  def change do
    create table(:telemetry_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:device_id, references(:devices, on_delete: :delete_all, type: :binary_id), null: false)
      add(:timestamp, :utc_datetime, null: false)
      add(:payload, :map, default: "{}", null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:telemetry_events, [:device_id]))
    create(index(:telemetry_events, [:timestamp]))
    create(index(:telemetry_events, [:payload], using: :gin))
  end
end
