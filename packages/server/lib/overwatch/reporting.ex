defmodule Nixstasis.Reporting do
  @moduledoc """
  The Reporting context.
  """

  import Ecto.Query, only: [from: 2]

  alias Nixstasis.Domain
  alias Nixstasis.Repo
  alias Nixstasis.Reporting.CustomReport

  def list_custom_reports do
    Domain.list_custom_reports!()
  end

  def get_custom_report!(id), do: Domain.get_custom_report!(id)

  def create_custom_report(attrs \\ %{}) do
    Domain.create_custom_report(attrs)
  end

  def custom_report_name_taken?(name) when is_binary(name) and name != "" do
    normalized_name = String.trim(name)

    if normalized_name == "" do
      false
    else
      query =
        from(r in "custom_reports",
          where: fragment("lower(?) = lower(?)", r.name, ^normalized_name),
          select: 1,
          limit: 1
        )

      Repo.one(query) == 1
    end
  end

  def custom_report_name_taken?(_), do: false

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
