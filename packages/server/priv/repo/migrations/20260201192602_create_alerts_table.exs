defmodule Nixstasis.Repo.Migrations.CreateAlertsTable do
  use Ecto.Migration

  def change do
    create table(:alerts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:device_id, references(:devices, on_delete: :delete_all, type: :binary_id), null: false)
      # Nullable for system alerts (like offline)
      add(:rule_id, :binary_id)
      # offline, threshold
      add(:type, :string, null: false)
      # active, resolved, acknowledged
      add(:status, :string, default: "active", null: false)
      add(:message, :string, null: false)
      add(:triggered_at, :utc_datetime, default: fragment("now()"), null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:alerts, [:device_id]))
    create(index(:alerts, [:status]))
    create(index(:alerts, [:type]))
    create(index(:alerts, [:triggered_at]))
  end
end
