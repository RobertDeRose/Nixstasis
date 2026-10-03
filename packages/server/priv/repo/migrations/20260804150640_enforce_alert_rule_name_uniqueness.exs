defmodule Nixstasis.Repo.Migrations.EnforceAlertRuleNameUniqueness do
  @moduledoc """
  Enforces global case-insensitive uniqueness for alert rule names.

  Existing case-insensitive duplicates fail this migration with their names and
  IDs so operators can reconcile them without silent data changes.
  """

  use Ecto.Migration

  def up do
    execute("""
    DO $$
    DECLARE
      duplicate_names text;
    BEGIN
      SELECT string_agg(
        format('%L (ids: %s)', representative_name, ids),
        '; '
      )
      INTO duplicate_names
      FROM (
        SELECT
          min(name) AS representative_name,
          string_agg(id::text, ', ' ORDER BY id) AS ids
        FROM alert_rules
        GROUP BY lower(name)
        HAVING count(*) > 1
      ) duplicates;

      IF duplicate_names IS NOT NULL THEN
        RAISE EXCEPTION
          'Cannot enforce case-insensitive alert rule name uniqueness; resolve duplicates first: %',
          duplicate_names;
      END IF;
    END
    $$;
    """)

    execute("DROP INDEX IF EXISTS alert_rules_name_index")

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS alert_rules_unique_name_index
    ON alert_rules (lower(name))
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS alert_rules_unique_name_index")
    execute("CREATE INDEX IF NOT EXISTS alert_rules_name_index ON alert_rules (name)")
  end
end
