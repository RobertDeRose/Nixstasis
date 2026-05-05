defmodule Nixstasis.Repo.Migrations.AddAlertRuleName do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :name, :text, null: false, default: "Untitled rule"
    end

    create index(:alert_rules, [:name])
  end
end
