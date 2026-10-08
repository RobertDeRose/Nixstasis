defmodule NixstasisWeb.ReportResultController do
  use NixstasisWeb, :controller

  alias Nixstasis.Reporting
  alias NixstasisWeb.OperatorContext
  alias NixstasisWeb.Permissions

  @doc """
  Returns a custom report's selected fields and result rows for an operator.

  Requires verified authentication and report-view permission, and supplies the
  operator's device scope separately from the 250-row preview options. Missing
  authentication returns 401, missing permission returns 403, and unavailable
  reports or failed result queries return 404. Success retains `data.fields`
  and `data.rows` rather than exposing resource CRUD output.
  """
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

  # Resolve verified proxy claims or the explicitly enabled local-development
  # fallback; normalize authentication failures into an unauthorized result.
  defp operator_context(conn) do
    case OperatorContext.from_conn(conn) do
      {:ok, context} -> {:ok, context}
      :local_development -> {:ok, OperatorContext.local_development_permissions()}
      :error -> {:error, :unauthorized}
    end
  end
end
