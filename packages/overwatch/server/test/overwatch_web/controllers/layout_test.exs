defmodule NixstasisWeb.LayoutTest do
  use NixstasisWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  test "renders main layout structure with sidebar/drawer", %{conn: conn} do
    # Using the dashboard route which uses the default app layout
    {:ok, _view, html} = live(conn, "/")

    # Check for the drawer container
    assert html =~ "drawer"
    assert html =~ "drawer-content"
    assert html =~ "drawer-side"

    # Check for sidebar overlay (for mobile)
    assert html =~ "drawer-overlay"
  end

  test "renders navigation items in sidebar", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Check for expected navigation links
    assert has_element?(view, ~s|a[href="/"]|, "Dashboard")
    assert has_element?(view, ~s|a[href="/devices"]|, "Devices")
    assert has_element?(view, ~s|a[href="/alerts"]|, "Alerts")
    assert has_element?(view, ~s|a[href="/reports"]|, "Reports")
    assert has_element?(view, ~s|a[href="/settings"]|, "Settings")
  end

  test "renders mobile bottom navigation when on small screens", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    # Verify bottom nav container exists and is visible only on mobile (lg:hidden)
    # Note: We changed "btm-nav" to a custom floating dock style, so we check for the container classes
    assert html =~ "fixed bottom-4"
    assert html =~ "lg:hidden"

    # Verify it contains the mobile links using aria-labels we added
    assert has_element?(view, "a[aria-label='Dashboard']")
    assert has_element?(view, "a[aria-label='Devices']")
  end

  test "renders theme toggle", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Check for the theme toggle buttons
    assert has_element?(view, "[data-phx-theme='light']")
    assert has_element?(view, "[data-phx-theme='dark']")
    assert has_element?(view, "[data-phx-theme='system']")
  end
end
