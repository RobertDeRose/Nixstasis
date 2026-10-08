defmodule NixstasisWeb.ReportResultControllerTest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring.Telemetry
  alias Nixstasis.Repo
  alias Nixstasis.Reporting

  setup do
    previous = Application.get_env(:nixstasis, :local_browser_auth_fallback?, false)
    Application.put_env(:nixstasis, :local_browser_auth_fallback?, false)

    on_exit(fn -> Application.put_env(:nixstasis, :local_browser_auth_fallback?, previous) end)

    {:ok, allowed_device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EF:01",
        product_name: "report-result-allowed"
      })

    {:ok, other_device} =
      Devices.register_device(%{
        mac_address: "AA:BB:CC:DD:EF:02",
        product_name: "report-result-other"
      })

    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%Telemetry{
      device_id: allowed_device.id,
      payload: %{"marker" => "allowed"},
      timestamp: timestamp
    })

    Repo.insert!(%Telemetry{
      device_id: other_device.id,
      payload: %{"marker" => "other"},
      timestamp: timestamp
    })

    {:ok, report} =
      Reporting.create_custom_report(%{
        "name" => "Scoped result endpoint",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "marker", "alias" => "marker"}],
          "filters" => []
        }
      })

    %{allowed_device: allowed_device, other_device: other_device, report: report}
  end

  test "requires verified operator authentication", %{conn: conn, report: report} do
    conn = get(conn, ~p"/api/v1/reports/#{report.id}/results")
    assert response(conn, 401) == ""
  end

  test "does not trust forged operator claims without the proxy credential", %{conn: conn, report: report} do
    conn =
      conn
      |> put_req_header("x-token-user-roles", "nixstasis/admin")
      |> get(~p"/api/v1/reports/#{report.id}/results")

    assert response(conn, 401) == ""
  end

  test "limits telemetry rows to the operator device scope", %{
    conn: conn,
    allowed_device: allowed_device,
    report: report
  } do
    conn =
      conn
      |> trusted_viewer()
      |> put_req_header("x-token-device-ids", allowed_device.id)
      |> get(~p"/api/v1/reports/#{report.id}/results")

    assert %{"data" => %{"rows" => [%{"marker" => "allowed"}]}} = json_response(conn, 200)
  end

  test "retains fleet-wide report access for an explicitly unscoped operator", %{conn: conn, report: report} do
    conn =
      conn
      |> trusted_viewer()
      |> get(~p"/api/v1/reports/#{report.id}/results")

    rows = json_response(conn, 200)["data"]["rows"]
    assert MapSet.new(Enum.map(rows, & &1["marker"])) == MapSet.new(["allowed", "other"])
  end

  # Authenticate the test viewer through proxy headers without adding a device
  # restriction; individual tests supply a scope when they need one.
  defp trusted_viewer(conn) do
    conn
    |> put_req_header("x-token-user-roles", "nixstasis/viewer")
    |> put_trusted_proxy_auth()
  end
end
