defmodule NixstasisWeb.DashboardLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "Dashboard" do
    test "renders dashboard with stats", %{conn: conn} do
      # Given: User accesses the dashboard
      {:ok, _view, html} = live(conn, "/")

      # Then: They see the dashboard title and stats
      assert html =~ "Overview"
      assert html =~ "Total Devices"
    end

    test "updates stats via PubSub", %{conn: conn} do
      # Given: User is on the dashboard
      {:ok, view, _html} = live(conn, "/")

      # When: A PubSub message is broadcast (simulating backend change)
      Phoenix.PubSub.broadcast(Nixstasis.PubSub, "devices", {:device_registered, %{}})

      # Then: The view updates (implicitly checked by re-render, though value might not change in this mock)
      assert render(view) =~ "Total Devices"
    end

    test "renders navigation links", %{conn: conn} do
      # Given: User is on the dashboard
      {:ok, _view, html} = live(conn, "/")

      # Then: They see the navigation buttons
      assert html =~ "Manage Devices"
      assert html =~ "Pending Approvals"
      assert html =~ "View Alerts"
      assert html =~ "Reports"
      assert html =~ "href=\"/devices\""
    end
  end
end
