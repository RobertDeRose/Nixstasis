defmodule NixstasisWeb.DeviceLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Nixstasis.Devices

  @base_attrs %{
    account_number: "123456789",
    approval_status: :approved,
    product_name: "PROD-1",
    last_seen_at: DateTime.utc_now()
  }

  defp create_device!(attrs) do
    {:ok, device} = Devices.create_device(Map.merge(@base_attrs, attrs))
    device
  end

  describe "Device Index filters and table" do
    test "renders MAC Address and Product columns", %{conn: conn} do
      _ = create_device!(%{mac_address: "AA:AA:AA:AA:AA:AA", product_name: "Alpha"})
      {:ok, _view, html} = live(conn, ~p"/devices")

      assert html =~ "MAC Address"
      assert html =~ "Product"
    end

    test "adds additive filters by clicking product/status/account and supports clear", %{conn: conn} do
      _ = create_device!(%{mac_address: "AA:AA:AA:AA:AA:AA", product_name: "Alpha", approval_status: :pending})
      _ = create_device!(%{mac_address: "BB:BB:BB:BB:BB:BB", product_name: "Alpha", approval_status: :approved})
      _ = create_device!(%{mac_address: "CC:CC:CC:CC:CC:CC", product_name: "Beta", approval_status: :pending})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element("a", "Pending")
      |> render_click()

      assert render(view) =~ "Status: pending"
      refute render(view) =~ "BB:BB:BB:BB:BB:BB"

      view
      |> element("a[href*='product=Alpha']", "Alpha")
      |> render_click()

      assert render(view) =~ "Product: Alpha"
      refute render(view) =~ "CC:CC:CC:CC:CC:CC"

      view
      |> element("a[href*='account_number=123456789']", "123456789")
      |> render_click()

      assert render(view) =~ "Account number: 123456789"
      assert render(view) =~ "Active filters:"

      view
      |> element("button[phx-click='clear_filters']")
      |> render_click()

      refute render(view) =~ "Active filters:"
    end

    test "navigates to device details from MAC address link", %{conn: conn} do
      device = create_device!(%{mac_address: "DD:DD:DD:DD:DD:DD"})
      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element("button[phx-click='open_device_details'][phx-value-id='#{device.id}']", "DD:DD:DD:DD:DD:DD")
      |> render_click()

      assert_redirect(view, "/devices/#{device.id}")
    end

    test "modal-open navigation p95 is within 2 seconds", %{conn: conn} do
      device = create_device!(%{mac_address: "AB:AB:AB:AB:AB:AB"})

      samples_ms =
        for _ <- 1..5 do
          {:ok, view, _html} = live(conn, ~p"/devices")
          start = System.monotonic_time(:millisecond)

          view
          |> element("button[phx-click='open_device_details'][phx-value-id='#{device.id}']", "AB:AB:AB:AB:AB:AB")
          |> render_click()

          assert_redirect(view, "/devices/#{device.id}")
          System.monotonic_time(:millisecond) - start
        end

      p95 =
        samples_ms
        |> Enum.sort()
        |> then(fn sorted -> Enum.at(sorted, ceil(length(sorted) * 0.95) - 1) end)

      assert p95 <= 2_000
    end
  end

  describe "Device Show behavior" do
    test "sets remote_access_requested to true on mount", %{conn: conn} do
      device = create_device!(%{mac_address: "EE:EE:EE:EE:EE:EE"})
      {:ok, _view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert Devices.get_device!(device.id).remote_access_requested == true
    end

    test "redirects with flash for missing device", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => "Device not found or unavailable"}}}} =
               live(conn, ~p"/devices/non-existent-id")
    end

    test "retry session reinitializes in place", %{conn: conn} do
      device = create_device!(%{mac_address: "FA:FA:FA:FA:FA:FA"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("button[phx-click='retry_session']", "Retry Session")
      |> render_click()

      assert render(view) =~ "Session reinitialized"
      assert render(view) =~ "Overview"
      assert render(view) =~ "PCP Data"
      assert render(view) =~ "Terminal"
    end
  end
end
