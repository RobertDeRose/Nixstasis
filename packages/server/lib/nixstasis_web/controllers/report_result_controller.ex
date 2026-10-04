defmodule NixstasisWeb.ReportResultController do
  use NixstasisWeb, :controller

  alias Nixstasis.Reporting
  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions

  def show(conn, %{"id" => id}) do
    with {:ok, operator_context} <- operator_context(conn),
         true <- Permissions.can_view_reports?(operator_context) do
      report = Reporting.get_custom_report!(id)
      authorized_device_ids = Permissions.authorized_report_device_ids(operator_context)

      json(conn, %{
        data: %{
          fields: Reporting.report_fields(report),
          rows: Reporting.run_custom_report(report, %{"limit" => 250}, authorized_device_ids)
        }
      })
    else
      {:error, :unauthorized} -> send_resp(conn, :unauthorized, "")
      false -> send_resp(conn, :forbidden, "")
    end
  rescue
    _error -> send_resp(conn, :not_found, "")
  end

  defp operator_context(conn) do
    case OperatorContext.from_conn(conn) do
      {:ok, context} -> {:ok, context}
      :local_development -> {:ok, OperatorContext.local_development_permissions()}
      :error -> {:error, :unauthorized}
    end
  end
end
