defmodule Nixstasis.Repo.Migrations.MakeCustomReportNameUniqueCaseInsensitive do
  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS custom_reports_unique_name_index")

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS custom_reports_unique_name_index
    ON custom_reports (lower(name))
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS custom_reports_unique_name_index")

    execute("""
    CREATE UNIQUE INDEX IF NOT EXISTS custom_reports_unique_name_index
    ON custom_reports (name)
    """)
  end
end
