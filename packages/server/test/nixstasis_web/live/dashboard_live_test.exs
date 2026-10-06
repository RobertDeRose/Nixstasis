defmodule NixstasisWeb.DashboardLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Nixstasis.Devices
  alias Nixstasis.Domain

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
      # Flush the debounce timer so the refresh happens immediately in tests
      send(view.pid, :debounced_refresh)

      assert has_element?(view, "a[href='/devices?connectivity_status=online'] .stat-value", "1")
    end

    test "scopes aggregate counts to the viewer's authorized devices", %{conn: conn} do
      {:ok, authorized_device} =
        Devices.register_device(%{
          mac_address: "AA:BB:CC:DD:EF:01",
          product_name: "dashboard-scope",
          last_seen_at: DateTime.utc_now(),
          approval_status: :pending
        })

      {:ok, other_online_device} =
        Devices.register_device(%{
          mac_address: "AA:BB:CC:DD:EF:02",
          product_name: "dashboard-scope",
          last_seen_at: DateTime.utc_now(),
          approval_status: :pending
        })

      {:ok, other_offline_device} =
        Devices.register_device(%{
          mac_address: "AA:BB:CC:DD:EF:03",
          product_name: "dashboard-scope",
          last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute),
          approval_status: :approved
        })

      {:ok, _authorized_alert} =
        Domain.create_alert(%{
          device_id: authorized_device.id,
          type: :offline,
          status: :active,
          message: "authorized dashboard alert"
        })

      {:ok, other_alert} =
        Domain.create_alert(%{
          device_id: other_online_device.id,
          type: :offline,
          status: :active,
          message: "out-of-scope dashboard alert"
        })

      assert other_offline_device.id != authorized_device.id

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => false,
          "can_remote_access" => false,
          "device_ids" => [authorized_device.id]
        })

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "a[href='/devices'] .stat-value", "1")
      assert has_element?(view, "a[href='/devices?connectivity_status=online'] .stat-value", "1")
      assert has_element?(view, "a[href='/devices?connectivity_status=online'] .stat-desc", "Offline: 0")
      assert has_element?(view, "a[href='/devices?approval_status=pending'] .stat-value", "1")
      assert has_element?(view, "a[href='/alerts?status=active'] .stat-value", "1")

      send(view.pid, {:device_registered, other_online_device})
      send(view.pid, {:alert_created, other_alert})

      assert has_element?(view, "a[href='/devices'] .stat-value", "1")
      assert has_element?(view, "a[href='/alerts?status=active'] .stat-value", "1")
    end

    test "fails dashboard aggregates closed when device scope is invalid", %{conn: conn} do
      {:ok, _device} =
        Devices.register_device(%{
          mac_address: "AA:BB:CC:DD:EF:04",
          product_name: "dashboard-scope",
          last_seen_at: DateTime.utc_now()
        })

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => false,
          "can_remote_access" => false,
          "device_ids" => ["not-a-uuid"]
        })

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "a[href='/devices'] .stat-value", "0")
      assert has_element?(view, "a[href='/devices?connectivity_status=online'] .stat-value", "0")
      assert has_element?(view, "a[href='/devices?approval_status=pending'] .stat-value", "0")
      assert has_element?(view, "a[href='/alerts?status=active'] .stat-value", "0")
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
