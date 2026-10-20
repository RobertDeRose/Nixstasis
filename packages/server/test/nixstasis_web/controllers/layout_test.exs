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

  test "theme toggle buttons are named and excluded from LiveView patching", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for {theme, label} <- [system: "Use system theme", light: "Use light theme", dark: "Use dark theme"] do
      assert has_element?(
               view,
               "#sidebar-theme-toggle[phx-update='ignore'] button[data-phx-theme='#{theme}'][aria-label='#{label}'][aria-pressed]"
             )
    end
  end

  test "marks the current page in both navigations", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/devices")

    assert has_element?(view, ".drawer-side a[href='/devices'][aria-current='page']", "Devices")
    assert has_element?(view, "nav a[aria-label='Devices'][aria-current='page']")
    refute has_element?(view, "a[href='/'][aria-current='page']")
  end

  test "the sidebar offers every palette from one list", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for {label, value} <- NixstasisWeb.Theme.palettes() do
      assert has_element?(view, "#sidebar-theme-toggle select[data-palette-select] option[value='#{value}']", label)
    end

    html = conn |> get("/") |> html_response(200)
    assert html =~ ~s(data-palettes="#{Enum.join(NixstasisWeb.Theme.palette_values(), " ")}")
    assert html =~ ~s(data-default-palette="#{NixstasisWeb.Theme.default_palette()}")
  end

  test "serves the UI font from the app", %{conn: conn} do
    conn = get(conn, "/fonts/noto-sans/noto-sans-latin-wght-normal.woff2")

    assert conn.status == 200
  end

  # The sidebar is hidden below lg with no opener, so Settings must offer the palette too.
  test "settings offers every palette", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("settings_permissions", %{"can_manage" => true})

    {:ok, view, _html} = live(conn, "/settings")

    assert has_element?(view, "#palette-picker[phx-update='ignore'] label[for='palette-select']")

    for {label, value} <- NixstasisWeb.Theme.palettes() do
      assert has_element?(view, "#palette-select[data-palette-select] option[value='#{value}']", label)
    end
  end

  test "settings offers highlight swatches on top of the palette", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("settings_permissions", %{"can_manage" => true})

    {:ok, view, _html} = live(conn, "/settings")

    for {label, value} <- NixstasisWeb.Theme.highlights() do
      assert has_element?(
               view,
               "#highlight-picker[phx-update='ignore'] input[type='radio'][data-highlight-select][value='#{value}']"
             )

      assert has_element?(view, "#highlight-picker label", label)
    end

    assert has_element?(view, "#highlight-picker label[data-highlight-preview='teal']")
    refute has_element?(view, "#highlight-picker label[data-highlight-preview='palette']")

    html = conn |> get("/") |> html_response(200)
    assert html =~ ~s(data-highlights="#{Enum.join(NixstasisWeb.Theme.highlight_values(), " ")}")
    assert html =~ ~s(data-default-highlight="#{NixstasisWeb.Theme.default_highlight()}")
  end

  test "brands the page title", %{conn: conn} do
    html = conn |> get("/settings") |> html_response(200)

    assert html =~ ~r/<title[^>]*>\s*Settings\s*· Nixstasis<\/title>/
  end
end
