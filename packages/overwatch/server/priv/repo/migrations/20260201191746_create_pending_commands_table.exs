defmodule Nixstasis.Repo.Migrations.CreatePendingCommandsTable do
  use Ecto.Migration

  def change do
    create table(:pending_commands, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:device_id, references(:devices, on_delete: :delete_all, type: :binary_id), null: false)
      add(:command_payload, :map, default: "{}", null: false)
      add(:status, :string, default: "queued", null: false)
      add(:queued_at, :utc_datetime, default: fragment("now()"))
      add(:delivered_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:pending_commands, [:device_id]))
    create(index(:pending_commands, [:status]))
  end
end
