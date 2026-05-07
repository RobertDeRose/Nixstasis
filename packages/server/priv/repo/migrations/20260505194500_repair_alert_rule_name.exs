defmodule Nixstasis.Repo.Migrations.RepairAlertRuleName do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE alert_rules ADD COLUMN IF NOT EXISTS name text NOT NULL DEFAULT 'Untitled rule'")

    execute("CREATE INDEX IF NOT EXISTS alert_rules_name_index ON alert_rules (name)")
  end

  def down do
    execute("DROP INDEX IF EXISTS alert_rules_name_index")
    execute("ALTER TABLE alert_rules DROP COLUMN IF EXISTS name")
  end
end
