defmodule Nixstasis.Reporting do
  @moduledoc """
  The Reporting context.
  """

  alias Nixstasis.Domain
  alias Nixstasis.Reporting.CustomReport

  def list_custom_reports do
    Domain.list_custom_reports!()
  end

  def get_custom_report!(id), do: Domain.get_custom_report!(id)

  def create_custom_report(attrs \\ %{}) do
    Domain.create_custom_report(attrs)
  end

  def update_custom_report(%CustomReport{} = report, attrs) do
    Domain.update_custom_report(report, attrs)
  end

  def delete_custom_report(%CustomReport{} = report) do
    Domain.destroy_custom_report(report)
  end

  def change_custom_report(report, attrs \\ %{})

  def change_custom_report(%CustomReport{id: nil}, attrs) do
    CustomReport
    |> AshPhoenix.Form.for_create(:create, domain: Domain, params: attrs)
  end

  def change_custom_report(%CustomReport{} = report, attrs) do
    report
    |> AshPhoenix.Form.for_update(:update, domain: Domain, params: attrs)
  end
end
