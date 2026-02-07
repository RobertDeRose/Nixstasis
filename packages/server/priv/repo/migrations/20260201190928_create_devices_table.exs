defmodule Nixstasis.Repo.Migrations.CreateDevicesTable do
  use Ecto.Migration

  def change do
    # 1. Create the custom Enum type in Postgres
    # (The second argument is the SQL for 'down' / rollback)
    execute(
      "CREATE TYPE approval_status AS ENUM ('pending', 'approved', 'rejected')",
      "DROP TYPE approval_status"
    )

    create table(:devices, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:mac_address, :string, null: false)
      add(:product_name, :string)
      add(:account_number, :string)
      add(:last_seen_at, :utc_datetime)
      add(:approval_status, :approval_status, default: "pending", null: false)
      add(:schema, :map, default: %{}, null: false)
      add(:metadata, :map, default: %{}, null: false)
      add(:remote_access_requested, :boolean, default: false, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:devices, [:mac_address]))
    create(index(:devices, [:account_number]))
    create(index(:devices, [:product_name]))
    create(index(:devices, [:approval_status]))
    create(index(:devices, [:metadata], using: :gin))
  end
end
