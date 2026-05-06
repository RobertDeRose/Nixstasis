defmodule Nixstasis.Repo.Migrations.CreateReportViewPreferences do
  use Ecto.Migration

  def change do
    execute(
      """
      CREATE TABLE IF NOT EXISTS report_view_preferences (
        id bigserial PRIMARY KEY,
        scope text NOT NULL,
        view_key text NOT NULL,
        preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
        inserted_at timestamp(6) without time zone NOT NULL,
        updated_at timestamp(6) without time zone NOT NULL
      )
      """,
      "DROP TABLE IF EXISTS report_view_preferences"
    )

    execute(
      """
      CREATE UNIQUE INDEX IF NOT EXISTS report_view_preferences_scope_view_key_index
      ON report_view_preferences (scope, view_key)
      """,
      "DROP INDEX IF EXISTS report_view_preferences_scope_view_key_index"
    )
  end
end
