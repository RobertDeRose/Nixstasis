defmodule Nixstasis.Reporting do
  @moduledoc """
  The Reporting context.
  """
  import Ecto.Query, warn: false
  alias Nixstasis.Repo
  alias Nixstasis.Reporting.CustomReport

  def list_custom_reports do
    Repo.all(CustomReport)
  end

  def get_custom_report!(id), do: Repo.get!(CustomReport, id)

  def create_custom_report(attrs \\ %{}) do
    %CustomReport{}
    |> CustomReport.changeset(attrs)
    |> Repo.insert()
  end

  def update_custom_report(%CustomReport{} = report, attrs) do
    report
    |> CustomReport.changeset(attrs)
    |> Repo.update()
  end

  def delete_custom_report(%CustomReport{} = report) do
    Repo.delete(report)
  end

  def change_custom_report(%CustomReport{} = report, attrs \\ %{}) do
    CustomReport.changeset(report, attrs)
  end
end
