defmodule Nixstasis.Repo.Migrations.CreateDevicesTable do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:mac_address, :string, null: false)
      add(:approval_status, :string, default: "pending", null: false)
      add(:schema_definition, :map, default: "{}", null: false)
      add(:last_seen_at, :utc_datetime)
      add(:metadata, :map, default: "{}", null: false)
      add(:remote_access_requested, :boolean, default: false, null: false)
      add(:product_name, :string)
      add(:account_number, :string)
      add(:ipv4_address, :string)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:devices, [:mac_address]))
    create(index(:devices, [:account_number]))
    create(index(:devices, [:product_name]))
    create(index(:devices, [:approval_status]))
    create(index(:devices, [:schema_definition], using: :gin))
  end
end
