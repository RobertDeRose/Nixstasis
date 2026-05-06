defmodule Nixstasis.Repo.Migrations.RepairDeviceIpv4Address do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE devices ADD COLUMN IF NOT EXISTS ipv4_address text")

    execute(
      "UPDATE devices SET ipv4_address = metadata->>'ip_address' WHERE ipv4_address IS NULL AND metadata ? 'ip_address'"
    )

    execute("CREATE INDEX IF NOT EXISTS devices_ipv4_address_index ON devices (ipv4_address)")
  end

  def down do
    execute("DROP INDEX IF EXISTS devices_ipv4_address_index")
    execute("ALTER TABLE devices DROP COLUMN IF EXISTS ipv4_address")
  end
end
