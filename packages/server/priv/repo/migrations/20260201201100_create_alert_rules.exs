defmodule Nixstasis.Repo.Migrations.CreateAlertRules do
  use Ecto.Migration

  def change do
    create table(:alert_rules) do
      add(:product_name, :string, null: false)
      add(:condition_field, :string, null: false)
      add(:operator, :string, null: false)
      add(:threshold_value, :string, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:alert_rules, [:product_name]))
  end
end
