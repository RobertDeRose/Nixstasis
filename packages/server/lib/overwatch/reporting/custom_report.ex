defmodule Nixstasis.Reporting.CustomReport do
  @moduledoc """
  Schema for persisted custom report definitions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "custom_reports" do
    field(:name, :string)
    field(:config, :map)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(custom_report, attrs) do
    custom_report
    |> cast(attrs, [:name, :config])
    |> validate_required([:name, :config])
  end
end
