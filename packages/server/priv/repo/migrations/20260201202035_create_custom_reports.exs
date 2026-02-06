defmodule Nixstasis.Repo.Migrations.CreateCustomReports do
  use Ecto.Migration

  def change do
    create table(:custom_reports) do
      add(:name, :string, null: false)
      add(:config, :map, null: false)

      timestamps(type: :utc_datetime)
    end
  end
end
