defmodule Nixstasis.Repo.Migrations.CreateSystemSettingsTable do
  use Ecto.Migration

  def change do
    create table(:system_settings, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:key, :string, null: false)
      add(:value, :map, default: "{}", null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:system_settings, [:key]))
  end
end
