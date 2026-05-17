defmodule Nixstasis.Repo.Migrations.AddDeviceIpv4Address do
  use Ecto.Migration

  def change do
    alter table(:devices) do
      add(:ipv4_address, :text)
    end

    execute(
      "UPDATE devices SET ipv4_address = metadata->>'ip_address' WHERE ipv4_address IS NULL AND metadata ? 'ip_address'",
      "UPDATE devices SET metadata = metadata"
    )

    create(index(:devices, [:ipv4_address]))
    create(index(:devices, [:schema], using: "gin"))

    execute(
      "CREATE INDEX devices_product_schema_version_index ON devices (product_name, ((schema->>'version'))) WHERE product_name IS NOT NULL AND schema <> '{}'::jsonb",
      "DROP INDEX IF EXISTS devices_product_schema_version_index"
    )
  end
end
