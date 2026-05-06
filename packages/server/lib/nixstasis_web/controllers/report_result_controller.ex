defmodule NixstasisWeb.ReportResultController do
  use NixstasisWeb, :controller

  alias Nixstasis.Reporting

  def show(conn, %{"id" => id}) do
    report = Reporting.get_custom_report!(id)

    json(conn, %{
      data: %{
        fields: Reporting.report_fields(report),
        rows: Reporting.run_custom_report(report, %{"limit" => 250})
      }
    })
  rescue
    _error -> send_resp(conn, :not_found, "")
  end
end
