defmodule NixstasisWeb.DeviceLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Nixstasis.Devices

  @create_attrs %{
    name: "Test Device",
    mac_address: "AA:BB:CC:DD:EE:FF",
    account_number: "123456789",
    firmware_version: "1.0.0",
    approval_status: "approved",
    product_name: "PROD-123"
  }

  defp create_device(_) do
    {:ok, device} =
      Devices.create_device(Map.merge(@create_attrs, %{last_seen_at: DateTime.utc_now()}))

    # Ensure it starts with remote_access_requested: false
    {:ok, device} = Devices.set_remote_access(device, false)
    %{device: device}
  end

  describe "Device Show" do
    setup [:create_device]

    test "mount sets remote_access_requested to true", %{conn: conn, device: device} do
      assert device.remote_access_requested == false

      {:ok, _view, _html} = live(conn, ~p"/devices/#{device}")

      updated_device = Devices.get_device!(device.id)
      assert updated_device.remote_access_requested == true
    end
  end

  describe "Device Index" do
    test "lists all devices", %{conn: conn} do
      {:ok, _d1} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "11:11:11:11:11:11",
            product_name: "D1"
        })

      {:ok, _d2} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "22:22:22:22:22:22",
            product_name: "D2"
        })

      {:ok, _view, html} = live(conn, ~p"/devices")

      assert html =~ "11:11:11:11:11:11"
      assert html =~ "22:22:22:22:22:22"
    end

    test "filters devices by status", %{conn: conn} do
      {:ok, _approved} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "AA:AA:AA:AA:AA:AA",
            product_name: "Approved Device",
            approval_status: "approved"
        })

      {:ok, _pending} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "BB:BB:BB:BB:BB:BB",
            approval_status: "pending",
            product_name: "Pending Device"
        })

      {:ok, view, _html} = live(conn, ~p"/devices")

      # Filter for pending
      html =
        view
        |> element("a", "Pending")
        |> render_click()

      assert html =~ "BB:BB:BB:BB:BB:BB"
      refute html =~ "AA:AA:AA:AA:AA:AA"

      # Filter for all (reset)
      html =
        view
        |> element("a", "All")
        |> render_click()

      assert html =~ "AA:AA:AA:AA:AA:AA"
      assert html =~ "BB:BB:BB:BB:BB:BB"
    end

    test "sorts devices", %{conn: conn} do
      {:ok, _d1} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "11:11:11:11:11:11",
            product_name: "A-Device"
        })

      {:ok, _d2} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "99:99:99:99:99:99",
            product_name: "Z-Device"
        })

      {:ok, view, _html} = live(conn, ~p"/devices")

      # Click "Device Name" header to sort by MAC address
      view
      |> element("th", "Device Name")
      |> render_click()

      # Ascending (11... before 99...)
      assert render(view) =~ ~r/11:11:11:11:11:11.*99:99:99:99:99:99/s

      # Descending (99... before 11...)
      view
      |> element("th", "Device Name")
      |> render_click()

      assert render(view) =~ ~r/99:99:99:99:99:99.*11:11:11:11:11:11/s
    end

    test "bulk approves devices", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "CC:CC:CC:CC:CC:CC",
            approval_status: "pending",
            product_name: "To Approve"
        })

      {:ok, view, _html} = live(conn, ~p"/devices?status=pending")

      # Select the device
      view
      |> element("#devices-#{device.id} input[type=checkbox]")
      |> render_click()

      # Click Bulk Approve
      view
      |> element("button", "Approve")
      |> render_click()

      {path, flash} = assert_redirect(view)
      assert path == "/devices"
      assert flash["info"] == "Devices approved"

      updated_device = Devices.get_device!(device.id)
      assert updated_device.approval_status == "approved"
    end

    test "bulk rejects devices", %{conn: conn} do
      {:ok, device} =
        Devices.create_device(%{
          @create_attrs
          | mac_address: "DD:DD:DD:DD:DD:DD",
            approval_status: "pending",
            product_name: "To Reject"
        })

      {:ok, view, _html} = live(conn, ~p"/devices?status=pending")

      # Select the device
      view
      |> element("#devices-#{device.id} input[type=checkbox]")
      |> render_click()

      # Click Bulk Reject
      view
      |> element("button", "Reject")
      |> render_click()

      {path, flash} = assert_redirect(view)
      assert path == "/devices"
      assert flash["info"] == "Devices rejected"

      updated_device = Devices.get_device!(device.id)
      assert updated_device.approval_status == "rejected"
    end
  end
end
