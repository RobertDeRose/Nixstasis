defmodule Nixstasis.Repo.Migrations.CreateReportViewPreferences do
  use Ecto.Migration

  def change do
    create table(:report_view_preferences, primary_key: false) do
      add :id, :bigserial, null: false, primary_key: true
      add :scope, :text, null: false
      add :view_key, :text, null: false
      add :preferences, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:report_view_preferences, [:scope, :view_key],
             name: "report_view_preferences_scope_view_key_index"
           )
  end
end
