defmodule Nixstasis.Monitoring.AlertRule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "alert_rules" do
    field(:product_key, :string)
    field(:condition_field, :string)
    field(:operator, :string)
    field(:threshold_value, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(alert_rule, attrs) do
    alert_rule
    |> cast(attrs, [:product_key, :condition_field, :operator, :threshold_value])
    |> validate_required([:product_key, :condition_field, :operator, :threshold_value])
    |> validate_inclusion(:operator, [">", "<", "=", "!=", ">=", "<="])
  end
end
