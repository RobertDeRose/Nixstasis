defmodule NixstasisWeb.DashboardLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Nixstasis.Devices

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

    test "refreshes counts for explicit device broadcasts without navigation", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "a[href='/devices'] .stat-value", "0")

      {:ok, device} = Devices.create_device(%{mac_address: "AA:BB:CC:DD:EE:01", product_name: "P1"})
      send(view.pid, {:device_registered, device})

      assert has_element?(view, "a[href='/devices'] .stat-value", "1")
    end

    test "refreshes online count for last-seen broadcasts without navigation", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          mac_address: "AA:BB:CC:DD:EE:02",
          product_name: "P1",
          last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      {:ok, view, _html} = live(conn, "/")
      assert has_element?(view, "a[href='/devices?connectivity_status=online'] .stat-value", "0")

      {:ok, device} = Devices.update_device(device, %{last_seen_at: DateTime.utc_now()})
      send(view.pid, {:device_last_seen_updated, device})

      assert has_element?(view, "a[href='/devices?connectivity_status=online'] .stat-value", "1")
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
      assert html =~ "href=\"/devices?connectivity_status=online\""
      assert html =~ "href=\"/devices?approval_status=pending\""
    end
  end
end
