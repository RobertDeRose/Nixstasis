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

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("device_permissions", %{"can_view" => true, "can_remote_access" => true})

    {:ok, conn: conn}
  end

  describe "Device Index filters and table" do
    test "manual device creation schedules a scoped success flash timeout", %{conn: conn} do
      previous_timeout = Application.get_env(:nixstasis, :device_success_flash_timeout_ms)
      assert NixstasisWeb.DeviceLive.FormComponent.success_flash_timeout_ms() == 30_000
      Application.put_env(:nixstasis, :device_success_flash_timeout_ms, 60)

      on_exit(fn ->
        if is_nil(previous_timeout) do
          Application.delete_env(:nixstasis, :device_success_flash_timeout_ms)
        else
          Application.put_env(:nixstasis, :device_success_flash_timeout_ms, previous_timeout)
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/devices/new")

      render_submit(element(view, "#device-form"), %{
        "device" => %{
          "mac_address" => "12:34:56:78:9A:BC",
          "account_number" => "987654321"
        }
      })

      assert_patch(view, ~p"/devices")
      assert render(view) =~ "Device created successfully"
      refute render(view) =~ ~s(id="flash-info")
      assert render(view) =~ ~s(id="flash-device-success")
      refute render(view) =~ ~s(id="flash-device-success" phx-mounted=)

      Process.sleep(25)
      assert render(view) =~ "Device created successfully"
      assert eventually_cleared?(view)
      refute render(view) =~ "Device created successfully"
    end

    test "renders MAC Address and Product columns", %{conn: conn} do
      _ =
        create_device!(%{
          mac_address: "AA:AA:AA:AA:AA:AA",
          product_name: "Alpha",
          ipv4_address: "10.0.0.10"
        })

      {:ok, _view, html} = live(conn, ~p"/devices")

      assert html =~ "MAC Address"
      assert html =~ "Product"
      assert html =~ "IPv4"
      assert html =~ "10.0.0.10"
    end

    test "adds additive filters by clicking product/approval/account and supports clear", %{conn: conn} do
      _ = create_device!(%{mac_address: "AA:AA:AA:AA:AA:AA", product_name: "Alpha", approval_status: :pending})
      _ = create_device!(%{mac_address: "BB:BB:BB:BB:BB:BB", product_name: "Alpha", approval_status: :approved})
      _ = create_device!(%{mac_address: "CC:CC:CC:CC:CC:CC", product_name: "Beta", approval_status: :pending})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element("a", "Pending")
      |> render_click()

      assert render(view) =~ "Approval status: pending"
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

    test "filters by approval_status and connectivity_status params", %{conn: conn} do
      _pending_online =
        create_device!(%{
          mac_address: "11:11:11:11:11:11",
          approval_status: :pending,
          last_seen_at: DateTime.utc_now()
        })

      _approved_offline =
        create_device!(%{
          mac_address: "22:22:22:22:22:22",
          approval_status: :approved,
          last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute)
        })

      {:ok, _view, html} = live(conn, ~p"/devices?approval_status=pending")
      assert html =~ "11:11:11:11:11:11"
      refute html =~ "22:22:22:22:22:22"

      {:ok, _view, html} = live(conn, ~p"/devices?connectivity_status=offline")
      assert html =~ "22:22:22:22:22:22"
      refute html =~ "11:11:11:11:11:11"
    end

    test "filters, searches, and sorts by dedicated IPv4 address", %{conn: conn} do
      _ = create_device!(%{mac_address: "A1:A1:A1:A1:A1:A1", ipv4_address: "10.10.10.1"})
      _ = create_device!(%{mac_address: "B2:B2:B2:B2:B2:B2", ipv4_address: "10.10.10.2"})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element("a[href*='ipv4_address=10.10.10.1']", "10.10.10.1")
      |> render_click()

      assert render(view) =~ "Ipv4 address: 10.10.10.1"
      assert render(view) =~ "A1:A1:A1:A1:A1:A1"
      refute render(view) =~ "B2:B2:B2:B2:B2:B2"

      {:ok, _view, search_html} = live(conn, ~p"/devices?search=10.10.10.2")
      assert search_html =~ "B2:B2:B2:B2:B2:B2"
      refute search_html =~ "A1:A1:A1:A1:A1:A1"

      {:ok, _view, sort_html} = live(conn, ~p"/devices?sort_by=ipv4_address&sort_order=asc")
      assert sort_html =~ "10.10.10.1"
      assert sort_html =~ "10.10.10.2"
    end

    test "navigates to device details from MAC address link", %{conn: conn} do
      device = create_device!(%{mac_address: "DD:DD:DD:DD:DD:DD"})
      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element(
        "button[phx-click='open_device_details'][phx-value-id='#{device.id}']",
        "DD:DD:DD:DD:DD:DD"
      )
      |> render_click()

      assert_redirect(view, "/devices/#{device.id}")
    end

    test "device details navigation is blocked for unauthorized sessions", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:01"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => false})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element(
        "button[phx-click='open_device_details'][phx-value-id='#{device.id}']",
        "DE:AD:BE:EF:00:01"
      )
      |> render_click()

      assert render(view) =~ "not authorized to view device details"
    end

    test "device details navigation is blocked when permission context is missing", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:02"})

      conn = conn |> recycle() |> init_test_session(%{})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element(
        "button[phx-click='open_device_details'][phx-value-id='#{device.id}']",
        "DE:AD:BE:EF:00:02"
      )
      |> render_click()

      assert render(view) =~ "not authorized to view device details"
    end

    test "device details navigation is blocked when session is scoped to another device", %{conn: conn} do
      allowed = create_device!(%{mac_address: "DE:AD:BE:EF:00:03"})
      blocked = create_device!(%{mac_address: "DE:AD:BE:EF:00:04"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "device_id" => allowed.id})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element(
        "button[phx-click='open_device_details'][phx-value-id='#{blocked.id}']",
        "DE:AD:BE:EF:00:04"
      )
      |> render_click()

      assert render(view) =~ "not authorized to view device details"
    end

    test "device details navigation is blocked when scoped device list is empty", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:05"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "device_ids" => []})

      {:ok, view, _html} = live(conn, ~p"/devices")

      view
      |> element(
        "button[phx-click='open_device_details'][phx-value-id='#{device.id}']",
        "DE:AD:BE:EF:00:05"
      )
      |> render_click()

      assert render(view) =~ "not authorized to view device details"
    end

    test "device-details navigation p95 is within 2 seconds", %{conn: conn} do
      device = create_device!(%{mac_address: "AB:AB:AB:AB:AB:AB"})

      samples_ms =
        for _ <- 1..5 do
          {:ok, view, _html} = live(conn, ~p"/devices")
          start = System.monotonic_time(:millisecond)

          view
          |> element(
            "button[phx-click='open_device_details'][phx-value-id='#{device.id}']",
            "AB:AB:AB:AB:AB:AB"
          )
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
    test "rejects unauthorized device detail access before exposure", %{conn: conn} do
      device = create_device!(%{mac_address: "E0:E0:E0:E0:E0:E0"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => false})

      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => message}}}} =
               live(conn, ~p"/devices/#{device.id}")

      assert message =~ "not authorized"
    end

    test "rejects device detail access when permission context is missing", %{conn: conn} do
      device = create_device!(%{mac_address: "E0:E0:E0:E0:E0:E1"})

      conn = conn |> recycle() |> init_test_session(%{})

      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => message}}}} =
               live(conn, ~p"/devices/#{device.id}")

      assert message =~ "not authorized"
    end

    test "rejects device detail access when session is scoped to another device", %{conn: conn} do
      allowed = create_device!(%{mac_address: "E0:E0:E0:E0:E0:E2"})
      blocked = create_device!(%{mac_address: "E0:E0:E0:E0:E0:E3"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "device_ids" => [allowed.id]})

      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => message}}}} =
               live(conn, ~p"/devices/#{blocked.id}")

      assert message =~ "not authorized"
    end

    test "rejects device detail access when scoped device list is empty", %{conn: conn} do
      device = create_device!(%{mac_address: "E0:E0:E0:E0:E0:E4"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "can_remote_access" => true, "device_ids" => []})

      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => message}}}} =
               live(conn, ~p"/devices/#{device.id}")

      assert message =~ "not authorized"
    end

    test "sets remote_access_requested to true on mount", %{conn: conn} do
      device = create_device!(%{mac_address: "EE:EE:EE:EE:EE:EE"})
      {:ok, _view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert Devices.get_device!(device.id).remote_access_requested == true
    end

    test "explicit close clears remote access", %{conn: conn} do
      device = create_device!(%{mac_address: "E1:E1:E1:E1:E1:E1"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert Devices.get_device!(device.id).remote_access_requested == true

      render_hook(view, "close_remote_access", %{})

      assert Devices.get_device!(device.id).remote_access_requested == false
    end

    test "lease expiration clears remote access", %{conn: conn} do
      device = create_device!(%{mac_address: "E2:E2:E2:E2:E2:E2"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      %{remote_access_lease_ref: lease_ref} = :sys.get_state(view.pid).socket.assigns
      send(view.pid, {:remote_access_lease_expired, lease_ref})

      assert render(view) =~ "Remote access session expired"
      assert Devices.get_device!(device.id).remote_access_requested == false
    end

    test "owner death clears remote access lease", %{conn: conn} do
      device = create_device!(%{mac_address: "E3:E3:E3:E3:E3:E3"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert Devices.get_device!(device.id).remote_access_requested == true

      Ecto.Adapters.SQL.Sandbox.allow(
        Nixstasis.Repo,
        self(),
        Process.whereis(Nixstasis.Devices.RemoteAccessLeases)
      )

      ref = Process.monitor(view.pid)
      GenServer.stop(view.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}
      Devices.sync_remote_access_leases()

      assert Devices.get_device!(device.id).remote_access_requested == false
    end

    test "starting ssh session renders terminal socket token", %{conn: conn} do
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:E4"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      html =
        view
        |> element("button[phx-click='start_ssh_session']", "Start Remote Session")
        |> render_click()

      assert html =~ ~s(id="terminal-container")
      assert html =~ ~s(data-token=)
      assert html =~ ~s(data-socket-token=)

      %{terminal_socket_token: socket_token} = :sys.get_state(view.pid).socket.assigns

      assert {:ok, %{"device_id" => device_id}} =
               Phoenix.Token.verify(NixstasisWeb.Endpoint, "terminal_socket", socket_token, max_age: 3600)

      assert device_id == device.id
    end

    test "unauthorized sessions cannot start remote access", %{conn: conn} do
      device = create_device!(%{mac_address: "E5:E5:E5:E5:E5:E5"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "can_remote_access" => false})

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      html =
        view
        |> element("button[phx-click='start_ssh_session']", "Start Remote Session")
        |> render_click()

      assert html =~ "not authorized to start remote access"
      refute html =~ ~s(id="terminal-container")
      assert Devices.get_device!(device.id).remote_access_requested == false
    end

    test "missing remote-access permission does not auto-open a lease", %{conn: conn} do
      device = create_device!(%{mac_address: "E5:E5:E5:E5:E5:E6"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true})

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      refute Devices.get_device!(device.id).remote_access_requested

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      html =
        view
        |> element("button[phx-click='start_ssh_session']", "Start Remote Session")
        |> render_click()

      assert html =~ "not authorized to start remote access"
      refute Devices.get_device!(device.id).remote_access_requested
    end

    test "device detail refreshes when device state changes while mounted", %{conn: conn} do
      device = create_device!(%{mac_address: "E6:E6:E6:E6:E6:E6", last_seen_at: nil})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert render(view) =~ "Device Offline"

      {:ok, device} = Devices.get_device(device.id)
      {:ok, _updated} = Devices.update_device(device, %{last_seen_at: DateTime.utc_now()})

      assert eventually_rendered?(view, "Remote Access Requested:")
      refute render(view) =~ "Device Offline"
    end

    test "device detail refreshes when ordinary device attributes change while mounted", %{conn: conn} do
      device = create_device!(%{mac_address: "E6:E6:E6:E6:E6:E7", product_name: "Old Product"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert render(view) =~ "Old Product"

      {:ok, loaded_device} = Devices.get_device(device.id)
      {:ok, _updated} = Devices.update_device(loaded_device, %{product_name: "New Product"})

      assert eventually_rendered?(view, "New Product")
    end

    test "device detail clears remote access lease when device goes offline while mounted", %{conn: conn} do
      device = create_device!(%{mac_address: "E7:E7:E7:E7:E7:E7"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert Devices.get_device!(device.id).remote_access_requested == true

      {:ok, loaded_device} = Devices.get_device(device.id)

      {:ok, _updated} =
        Devices.update_device(loaded_device, %{last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute)})

      assert eventually_rendered?(view, "Device Offline")
      assert Devices.get_device!(device.id).remote_access_requested == false
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

  describe "Device Index selection refresh" do
    test "row checkbox state refreshes after toggling selection", %{conn: conn} do
      device = create_device!(%{mac_address: "C1:C1:C1:C1:C1:C1"})
      {:ok, view, _html} = live(conn, ~p"/devices")

      refute has_element?(view, "input[type='checkbox'][phx-value-id='#{device.id}'][checked]")

      view
      |> element("input[type='checkbox'][phx-value-id='#{device.id}']")
      |> render_click()

      assert has_element?(view, "input[type='checkbox'][phx-value-id='#{device.id}'][checked]")
    end

    test "toggle all only selects visible filtered devices", %{conn: conn} do
      alpha = create_device!(%{mac_address: "C2:C2:C2:C2:C2:C2", product_name: "Alpha"})
      _beta = create_device!(%{mac_address: "C3:C3:C3:C3:C3:C3", product_name: "Beta"})
      {:ok, view, _html} = live(conn, ~p"/devices?product=Alpha")

      view
      |> element("#select-all-checkbox")
      |> render_click()

      assert has_element?(view, "input[type='checkbox'][phx-value-id='#{alpha.id}'][checked]")
      refute has_element?(view, "input[type='checkbox'][phx-value-id='#{alpha.id}'][checked]", "") == false
      refute render(view) =~ "C3:C3:C3:C3:C3:C3"
    end

    test "device list refreshes when ordinary device attributes change while mounted", %{conn: conn} do
      device = create_device!(%{mac_address: "C4:C4:C4:C4:C4:C4", product_name: "Before Update"})
      {:ok, view, _html} = live(conn, ~p"/devices")

      assert render(view) =~ "Before Update"

      {:ok, loaded_device} = Devices.get_device(device.id)
      {:ok, _updated} = Devices.update_device(loaded_device, %{product_name: "After Update"})

      assert eventually_rendered?(view, "After Update")
    end
  end

  defp eventually_cleared?(view, attempts \\ 20)

  defp eventually_rendered?(view, text, attempts \\ 20)

  defp eventually_rendered?(view, text, attempts) when attempts > 0 do
    if render(view) =~ text do
      true
    else
      Process.sleep(5)
      eventually_rendered?(view, text, attempts - 1)
    end
  end

  defp eventually_rendered?(_view, _text, 0), do: false

  defp eventually_cleared?(view, attempts) when attempts > 0 do
    if render(view) =~ "Device created successfully" do
      Process.sleep(5)
      eventually_cleared?(view, attempts - 1)
    else
      true
    end
  end

  defp eventually_cleared?(_view, 0), do: false
end
