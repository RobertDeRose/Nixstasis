defmodule NixstasisWeb.DeviceLiveTest do
  use NixstasisWeb.ConnCase

  import ExUnit.CaptureLog
  import Phoenix.ChannelTest
  import Phoenix.LiveViewTest

  alias Ecto.Adapters.SQL.Sandbox
  alias Nixstasis.Devices
  alias Nixstasis.Devices.RemoteAccessLeases
  alias Nixstasis.Devices.SshKeyManager
  alias Nixstasis.Domain
  alias Nixstasis.Repo
  alias NixstasisWeb.DeviceLive.FormComponent

  @endpoint NixstasisWeb.Endpoint

  defmodule TerminalJourneySshClient do
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)
    def send_data(pid, data), do: GenServer.cast(pid, {:send_data, data})
    def stop(pid), do: GenServer.stop(pid)

    @impl true
    def init(opts) do
      {:ok, %{channel_pid: Keyword.fetch!(opts, :channel_pid)}}
    end

    @impl true
    def handle_cast({:send_data, data}, state) do
      send(state.channel_pid, {:ssh_output, output_for(data)})
      {:noreply, state}
    end

    defp output_for("printf nixstasis-smoke\n"), do: "nixstasis-smoke"
    defp output_for("whoami\n"), do: "nixstasis-support\n"
    defp output_for(data), do: data
  end

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

  defp group_authorization(device_ids) do
    %Nixstasis.Devices.GroupAuthorization{
      actor_id: "test-operator",
      can_manage_devices?: true,
      can_manage_all_devices?: is_nil(device_ids),
      authorized_device_ids: if(is_nil(device_ids), do: nil, else: MapSet.new(device_ids))
    }
  end

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("device_permissions", %{"can_view" => true, "can_manage" => true, "can_remote_access" => true})

    {:ok, conn: conn}
  end

  describe "Device Index filters and table" do
    test "manual device creation schedules a scoped success flash timeout", %{conn: conn} do
      previous_timeout = Application.get_env(:nixstasis, :device_success_flash_timeout_ms)
      assert FormComponent.success_flash_timeout_ms() == 30_000
      Application.put_env(:nixstasis, :device_success_flash_timeout_ms, 300)

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
      assert eventually_cleared?(view, 80)
      refute render(view) =~ "Device created successfully"
    end

    test "view-only sessions cannot add devices", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "can_manage" => false})

      {:ok, view, html} = live(conn, ~p"/devices")

      refute html =~ "Add Device"

      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => message}}}} = live(conn, ~p"/devices/new")
      assert message =~ "not authorized to manage devices"
      assert render(view) =~ "Devices"
    end

    test "scoped manage sessions cannot add devices", %{conn: conn} do
      allowed = create_device!(%{mac_address: "AA:AA:AA:AA:AA:AA"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "can_manage" => true, "device_ids" => [allowed.id]})

      {:ok, view, html} = live(conn, ~p"/devices")

      refute html =~ "Add Device"

      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => message}}}} = live(conn, ~p"/devices/new")
      assert message =~ "not authorized to manage devices"
      assert render(view) =~ "Devices"
    end

    test "unscoped managers complete the group metadata lifecycle", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      loading_html = view |> element("#manage-device-groups") |> render_click()
      assert loading_html =~ "Loading groups…"
      assert has_element?(view, "#device-group-panel[aria-labelledby='device-group-heading']")
      Process.sleep(15)
      assert render(view) =~ "No active groups yet"

      view |> element("#new-device-group") |> render_click()
      assert has_element?(view, "#device-group-form input[name='group[name]']")
      assert has_element?(view, "#device-group-form textarea[name='group[description]']")
      assert has_element?(view, "#device-group-form button[phx-disable-with='Saving…']")

      view
      |> form("#device-group-form", %{"group" => %{"name" => "Field units", "description" => "North site"}})
      |> render_submit()

      assert render(view) =~ "Group created"
      assert has_element?(view, "[data-group-name='Field units']")

      view |> element("button[phx-click='edit_group']", "Edit") |> render_click()

      view
      |> form("#device-group-form", %{"group" => %{"name" => "Field sensors", "description" => "North site"}})
      |> render_submit()

      assert render(view) =~ "Group updated"
      assert has_element?(view, "[data-group-name='Field sensors']")

      view |> element("button[phx-click='archive_group']", "Archive") |> render_click()
      refute has_element?(view, "[data-group-name='Field sensors']")

      view |> element("#toggle-archived-groups") |> render_click()
      assert has_element?(view, "[data-group-name='Field sensors']")
      assert has_element?(view, "button[phx-click='restore_group']", "Restore")

      view |> element("button[phx-click='restore_group']", "Restore") |> render_click()
      assert render(view) =~ "Group restored"

      view |> element("button[phx-click='archive_group']", "Archive") |> render_click()
      view |> element("button[phx-click='request_group_delete']", "Delete permanently") |> render_click()

      assert has_element?(view, "#confirm-group-delete[role='region'][tabindex='0']")
      assert has_element?(view, "#confirm-group-delete button[phx-disable-with='Deleting…']")

      render_keydown(view, "group_panel_keydown", %{"key" => "Escape"})
      refute has_element?(view, "#confirm-group-delete")
      assert has_element?(view, "#device-group-panel")

      view |> element("button[phx-click='request_group_delete']", "Delete permanently") |> render_click()
      view |> element("button[phx-click='confirm_group_delete']", "Delete permanently") |> render_click()
      assert render(view) =~ "Group permanently deleted"
      refute has_element?(view, "[data-group-name='Field sensors']")

      render_keydown(view, "group_panel_keydown", %{"key" => "Escape"})
      refute has_element?(view, "#device-group-panel")
    end

    test "group metadata UI reports name and nonempty deletion conflicts", %{conn: conn} do
      device = create_device!(%{mac_address: "AA:AA:AA:AA:AA:A1"})
      {:ok, existing} = Nixstasis.Domain.create_device_group(%{name: "Existing group"})

      {:ok, _membership} =
        Nixstasis.Domain.create_device_group_membership(%{
          group_id: existing.id,
          device_id: device.id
        })

      {:ok, _archived} =
        Nixstasis.Domain.update_device_group(existing, %{archived_at: DateTime.utc_now()})

      {:ok, view, _html} = live(conn, ~p"/devices")
      view |> element("#manage-device-groups") |> render_click()
      view |> element("#new-device-group") |> render_click()

      view
      |> form("#device-group-form", %{"group" => %{"name" => "EXISTING GROUP", "description" => ""}})
      |> render_submit()

      assert render(view) =~ "A group with that name already exists"

      view |> element("button[phx-click='cancel_group_form']", "Cancel") |> render_click()
      view |> element("#toggle-archived-groups") |> render_click()
      view |> element("button[phx-click='request_group_delete']", "Delete permanently") |> render_click()
      view |> element("button[phx-click='confirm_group_delete']", "Delete permanently") |> render_click()

      assert render(view) =~ "Remove every device before permanently deleting this group"
      assert has_element?(view, "[data-group-name='Existing group']")
    end

    test "group metadata handlers enforce resource length limits", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/devices")
      view |> element("#manage-device-groups") |> render_click()
      view |> element("#new-device-group") |> render_click()

      too_long_name = String.duplicate("n", 121)

      view
      |> form("#device-group-form", %{"group" => %{"name" => too_long_name, "description" => ""}})
      |> render_submit()

      assert render(view) =~ "Group names must be 120 characters or fewer"
      refute has_element?(view, "[data-group-name='#{too_long_name}']")

      view
      |> form("#device-group-form", %{"group" => %{"name" => "Bounded group", "description" => "Original"}})
      |> render_submit()

      view |> element("button[phx-click='edit_group']", "Edit") |> render_click()

      view
      |> form("#device-group-form", %{
        "group" => %{"name" => "Bounded group", "description" => String.duplicate("d", 501)}
      })
      |> render_submit()

      assert render(view) =~ "Group descriptions must be 500 characters or fewer"
      assert {:ok, [persisted]} = Nixstasis.Domain.list_device_groups()
      assert persisted.description == "Original"
    end

    test "scoped managers cannot invoke group metadata handlers", %{conn: conn} do
      allowed = create_device!(%{mac_address: "AA:AA:AA:AA:AA:A2"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("operator_context", %{"subject" => "scoped-manager"})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => true,
          "device_ids" => [allowed.id]
        })

      {:ok, view, _html} = live(conn, ~p"/devices")
      view |> element("#manage-device-groups") |> render_click()

      refute has_element?(view, "#new-device-group")
      render_hook(view, "new_group", %{})
      refute has_element?(view, "#device-group-form")

      render_hook(view, "archive_group", %{"id" => Ecto.UUID.generate()})
      assert render(view) =~ "not authorized to manage group metadata"
    end

    test "selected devices can be added to and removed from a visible group", %{conn: conn} do
      first = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B1"})
      second = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B2"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Selected workflow"})
      {:ok, view, _html} = live(conn, ~p"/devices")

      render_hook(view, "toggle_selection", %{"id" => first.id})
      render_hook(view, "toggle_selection", %{"id" => second.id})
      assert render(view) =~ "2 selected"
      assert has_element?(view, "#membership-group-select option[value='#{group.id}']")

      render_change(element(view, "#membership-group-form"), %{"group_id" => group.id})
      render_click(element(view, "#add-selected-to-group"))

      assert render(view) =~ "Added 2 devices to Selected workflow"

      assert MapSet.new(Devices.list_group_memberships(group.id, group_authorization(nil))) ==
               MapSet.new([first.id, second.id])

      render_click(element(view, "#add-selected-to-group"))
      assert render(view) =~ "Selected devices are already in Selected workflow"

      render_click(element(view, "#remove-selected-from-group"))
      assert render(view) =~ "Removed 2 devices from Selected workflow"
      assert Devices.list_group_memberships(group.id, group_authorization(nil)) == []
      assert render(view) =~ "2 selected"
    end

    test "scoped managers mutate memberships only in visible groups", %{conn: conn} do
      first = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B3"})
      second = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B4"})
      {:ok, visible_group} = Nixstasis.Domain.create_device_group(%{name: "Visible workflow"})
      {:ok, hidden_group} = Nixstasis.Domain.create_device_group(%{name: "Hidden workflow"})

      {:ok, _membership} =
        Nixstasis.Domain.create_device_group_membership(%{
          group_id: visible_group.id,
          device_id: first.id
        })

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("operator_context", %{"subject" => "scoped-manager"})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => true,
          "device_ids" => [first.id, second.id]
        })

      {:ok, view, _html} = live(conn, ~p"/devices")
      render_hook(view, "toggle_selection", %{"id" => second.id})

      assert has_element?(view, "#membership-group-select option[value='#{visible_group.id}']")
      refute has_element?(view, "#membership-group-select option[value='#{hidden_group.id}']")

      render_change(element(view, "#membership-group-form"), %{"group_id" => visible_group.id})
      render_click(element(view, "#add-selected-to-group"))

      assert MapSet.new(Devices.list_group_memberships(visible_group.id, group_authorization(nil))) ==
               MapSet.new([first.id, second.id])

      render_hook(view, "select_membership_group", %{"group_id" => hidden_group.id})
      render_click(element(view, "#add-selected-to-group"))
      assert render(view) =~ "That group is no longer available"
      assert Devices.list_group_memberships(hidden_group.id, group_authorization(nil)) == []
    end

    test "view-only sessions cannot invoke membership handlers", %{conn: conn} do
      device = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B5"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Denied workflow"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("operator_context", %{"subject" => "viewer"})
        |> put_session("device_permissions", %{"can_view" => true, "can_manage" => false})

      {:ok, view, _html} = live(conn, ~p"/devices")
      refute has_element?(view, "#membership-group-form")

      render_hook(view, "toggle_selection", %{"id" => device.id})
      render_hook(view, "select_membership_group", %{"group_id" => group.id})
      render_hook(view, "add_selected_to_group", %{})

      assert render(view) =~ "not authorized to manage group memberships"
      assert Devices.list_group_memberships(group.id, group_authorization(nil)) == []
    end

    test "membership handlers reject groups archived after selection", %{conn: conn} do
      device = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B6"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Stale workflow"})
      {:ok, view, _html} = live(conn, ~p"/devices")

      render_hook(view, "toggle_selection", %{"id" => device.id})
      render_change(element(view, "#membership-group-form"), %{"group_id" => group.id})
      {:ok, _archived} = Nixstasis.Domain.update_device_group(group, %{archived_at: DateTime.utc_now()})

      render_click(element(view, "#add-selected-to-group"))
      assert render(view) =~ "That group is archived or no longer available"
      assert Devices.list_group_memberships(group.id, group_authorization(nil)) == []
    end

    test "scoped removal clears a group selection when its final visible membership leaves", %{conn: conn} do
      device = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B7"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Last visible membership"})

      {:ok, _membership} =
        Nixstasis.Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("operator_context", %{"subject" => "scoped-manager"})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => true,
          "device_ids" => [device.id]
        })

      {:ok, view, _html} = live(conn, ~p"/devices")
      render_hook(view, "toggle_selection", %{"id" => device.id})
      render_change(element(view, "#membership-group-form"), %{"group_id" => group.id})
      render_click(element(view, "#remove-selected-from-group"))

      assert Devices.list_group_memberships(group.id, group_authorization(nil)) == []
      refute has_element?(view, "#membership-group-form")
      assert render(view) =~ "No visible groups are available"
    end

    test "membership UI rejects unauthorized and stale selected devices atomically", %{conn: conn} do
      first = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B8"})
      second = create_device!(%{mac_address: "AA:AA:AA:AA:AA:B9"})
      blocked = create_device!(%{mac_address: "AA:AA:AA:AA:AA:C0"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Atomic UI workflow"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("operator_context", %{"subject" => "scoped-manager"})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => true,
          "device_ids" => [first.id, second.id]
        })

      {:ok, _seed} =
        Nixstasis.Domain.create_device_group_membership(%{group_id: group.id, device_id: first.id})

      {:ok, view, _html} = live(conn, ~p"/devices")
      render_hook(view, "toggle_selection", %{"id" => first.id})
      render_hook(view, "toggle_selection", %{"id" => second.id})
      render_hook(view, "toggle_selection", %{"id" => blocked.id})
      assert render(view) =~ "not authorized to manage this device"
      assert render(view) =~ "2 selected"

      render_change(element(view, "#membership-group-form"), %{"group_id" => group.id})

      :sys.replace_state(view.pid, fn state ->
        %{state | socket: Phoenix.Component.assign(state.socket, :selected_ids, [first.id, blocked.id])}
      end)

      render_click(element(view, "#add-selected-to-group"))
      assert render(view) =~ "Your device access changed"
      assert Devices.list_group_memberships(group.id, group_authorization(nil)) == [first.id]

      :sys.replace_state(view.pid, fn state ->
        %{state | socket: Phoenix.Component.assign(state.socket, :selected_ids, [first.id, second.id])}
      end)

      assert :ok = Nixstasis.Domain.destroy_device(second)
      render_click(element(view, "#add-selected-to-group"))

      assert render(view) =~ "One or more selected devices are no longer available"
      assert Devices.list_group_memberships(group.id, group_authorization(nil)) == [first.id]
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

    test "group routes compose with existing filters and preserve generated navigation", %{conn: conn} do
      matching =
        create_device!(%{
          mac_address: "31:31:31:31:31:31",
          product_name: "Route sensor",
          approval_status: :pending,
          ipv4_address: "10.31.0.1"
        })

      excluded =
        create_device!(%{
          mac_address: "32:32:32:32:32:32",
          product_name: "Other sensor",
          approval_status: :approved,
          ipv4_address: "10.31.0.2"
        })

      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Route group"})

      for device <- [matching, excluded] do
        {:ok, _membership} =
          Nixstasis.Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})
      end

      params = %{
        "group_id" => group.id,
        "product" => matching.product_name,
        "account_number" => matching.account_number,
        "ipv4_address" => matching.ipv4_address,
        "approval_status" => "pending",
        "connectivity_status" => "online",
        "search" => "31:31",
        "sort_by" => "mac_address",
        "sort_order" => "asc"
      }

      {:ok, view, html} = live(conn, ~p"/devices?#{params}")

      assert html =~ matching.mac_address
      refute html =~ excluded.mac_address
      assert html =~ "Group: Route group"
      refute html =~ "Group: #{group.id}"
      assert has_element?(view, "[data-device-group-summary='#{matching.id}']", "Route group")
      assert has_element?(view, "th[data-group-summary-heading]")

      assert has_element?(
               view,
               "[data-device-group-summary='#{matching.id}'] a[href='#{~p"/devices?#{params}"}']",
               "Route group"
             )

      for label <- [matching.product_name, matching.account_number, matching.ipv4_address] do
        assert has_element?(view, "a[href*='group_id=#{group.id}']", label)
      end

      view |> element("th[phx-value-sort_by='account_number']") |> render_click()

      routed_params =
        params
        |> Map.put("sort_by", "account_number")
        |> Map.put("sort_order", :asc)

      assert_patch(view, ~p"/devices?#{routed_params}")

      assert has_element?(
               view,
               "a[href*='group_id=#{group.id}'][href*='approval_status=approved']",
               "Approved"
             )

      {:ok, _renamed} = Nixstasis.Domain.update_device_group(group, %{name: "Route group renamed"})
      send(view.pid, :device_groups_changed)
      assert render(view) =~ "Group: Route group renamed"

      view |> element("button[phx-value-key='product']") |> render_click()
      routed_params = Map.delete(routed_params, "product")
      assert_patch(view, ~p"/devices?#{routed_params}")

      view |> element("form[phx-change='search']") |> render_change(%{"search" => "31:31:31"})
      routed_params = Map.put(routed_params, "search", "31:31:31")
      assert_patch(view, ~p"/devices?#{routed_params}")

      view |> element("button[phx-click='clear_filters']") |> render_click()

      assert_patch(
        view,
        ~p"/devices?#{Map.take(routed_params, ["search", "sort_by", "sort_order"])}"
      )

      refute render(view) =~ "Group: Route group"
    end

    test "invalid, archived, and unauthorized group routes share an unavailable state", %{conn: conn} do
      allowed = create_device!(%{mac_address: "33:33:33:33:33:33"})
      blocked = create_device!(%{mac_address: "34:34:34:34:34:34"})
      {:ok, archived} = Nixstasis.Domain.create_device_group(%{name: "Archived secret"})
      {:ok, hidden} = Nixstasis.Domain.create_device_group(%{name: "Hidden secret"})

      for {group, device} <- [{archived, allowed}, {hidden, blocked}] do
        {:ok, _membership} =
          Nixstasis.Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})
      end

      {:ok, _archived} =
        Nixstasis.Domain.update_device_group(archived, %{archived_at: DateTime.utc_now()})

      conn =
        conn
        |> put_session("operator_context", %{"subject" => "scoped-viewer"})
        |> put_session("device_permissions", %{"can_view" => true, "device_ids" => [allowed.id]})

      for group_id <- ["not-a-uuid", archived.id, hidden.id] do
        {:ok, view, html} = live(conn, ~p"/devices?group_id=#{group_id}")

        assert html =~ "The requested group is unavailable"
        assert has_element?(view, "a", "Continue without group filter")
        refute html =~ allowed.mac_address
        refute html =~ blocked.mac_address
        refute html =~ "Archived secret"
        refute html =~ "Hidden secret"
        refute has_element?(view, "[data-group-filter-name]")
      end
    end

    test "scoped group routes expose only authorized memberships and counts", %{conn: conn} do
      allowed = create_device!(%{mac_address: "35:35:35:35:35:35"})
      blocked = create_device!(%{mac_address: "36:36:36:36:36:36"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Scoped route"})

      for device <- [allowed, blocked] do
        {:ok, _membership} =
          Nixstasis.Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})
      end

      conn =
        conn
        |> put_session("operator_context", %{"subject" => "scoped-viewer"})
        |> put_session("device_permissions", %{"can_view" => true, "device_ids" => [allowed.id]})

      {:ok, view, html} = live(conn, ~p"/devices?group_id=#{group.id}")

      assert html =~ allowed.mac_address
      refute html =~ blocked.mac_address
      assert html =~ "Group: Scoped route"
      assert has_element?(view, "[data-device-group-summary='#{allowed.id}']", "Scoped route")

      view |> element("#manage-device-groups") |> render_click()
      assert eventually_rendered?(view, "1 visible device")
      assert has_element?(view, "[data-group-name='Scoped route']", "1 visible device")

      {:ok, _archived} =
        Nixstasis.Domain.update_device_group(group, %{archived_at: DateTime.utc_now()})

      send(view.pid, :device_groups_changed)
      assert render(view) =~ "The requested group is unavailable"
      refute render(view) =~ allowed.mac_address
      refute has_element?(view, "[data-group-filter-name]")
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

      refute has_element?(view, "#devices-stream tr")
      assert render(view) =~ "not authorized to view devices"

      refute has_element?(
               view,
               "button[phx-click='open_device_details'][phx-value-id='#{device.id}']"
             )
    end

    test "device refresh events do not expose inventory to unauthorized sessions", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:08"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => false})

      {:ok, view, _html} = live(conn, ~p"/devices")

      send(view.pid, {:device_updated, device})

      refute has_element?(view, "#devices-stream tr")
      assert render(view) =~ "not authorized to view devices"
    end

    test "group invalidation re-queries scoped devices without consuming audit payloads", %{conn: conn} do
      allowed = create_device!(%{mac_address: "DE:AD:BE:EF:00:09"})
      blocked = create_device!(%{mac_address: "DE:AD:BE:EF:00:0A"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "device_ids" => [allowed.id]})

      {:ok, view, html} = live(conn, ~p"/devices")
      assert html =~ allowed.mac_address
      refute html =~ blocked.mac_address

      assert :ok = Nixstasis.Domain.destroy_device(allowed)

      send(view.pid, {
        :device_group_audit,
        %{actor_id: "sensitive-actor", device_ids: [blocked.id], action: :membership_add}
      })

      assert render(view) =~ allowed.mac_address
      refute render(view) =~ blocked.mac_address

      send(view.pid, :device_groups_changed)

      refute render(view) =~ allowed.mac_address
      refute render(view) =~ blocked.mac_address
    end

    test "device deletion refreshes scoped group counts, targets, and routes", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:0B"})
      {:ok, group} = Nixstasis.Domain.create_device_group(%{name: "Deletion refresh"})

      {:ok, _membership} =
        Nixstasis.Domain.create_device_group_membership(%{group_id: group.id, device_id: device.id})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("operator_context", %{"subject" => "scoped-manager"})
        |> put_session("device_permissions", %{
          "can_view" => true,
          "can_manage" => true,
          "device_ids" => [device.id]
        })

      {:ok, view, _html} = live(conn, ~p"/devices?group_id=#{group.id}")
      view |> element("#manage-device-groups") |> render_click()
      assert eventually_rendered?(view, "1 visible device")
      render_hook(view, "toggle_selection", %{"id" => device.id})
      render_change(element(view, "#membership-group-form"), %{"group_id" => group.id})

      assert :ok = Devices.delete_device(device)
      assert eventually_rendered?(view, "The requested group is unavailable")
      refute has_element?(view, "[data-group-name='Deletion refresh']")
      refute has_element?(view, "#membership-group-form")

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.selected_ids == []
      assert is_nil(assigns.selected_group_id)
      assert is_nil(assigns.filter_group_id)
      assert assigns.group_filter_unavailable?
    end

    test "device selection and bulk actions are blocked for view-only sessions", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:06", approval_status: :pending})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "can_manage" => false})

      {:ok, view, _html} = live(conn, ~p"/devices")

      refute has_element?(view, "input[phx-click='toggle_selection']")

      render_hook(view, "toggle_selection", %{"id" => device.id})
      assert render(view) =~ "not authorized to manage devices"

      render_hook(view, "bulk_approve", %{})
      assert Devices.get_device!(device.id).approval_status == :pending
    end

    test "bulk actions surface failures", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/devices")

      assert render_hook(view, "bulk_approve", %{}) =~ "Unable to approve selected devices."
      assert render_hook(view, "bulk_reject", %{}) =~ "Unable to reject selected devices."
    end

    test "device details navigation is blocked when permissions explicitly deny access", %{conn: conn} do
      _device = create_device!(%{mac_address: "DE:AD:BE:EF:00:02"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => false})

      {:ok, view, _html} = live(conn, ~p"/devices")

      refute has_element?(view, "#devices-stream tr")
      assert render(view) =~ "not authorized to view devices"
    end

    test "device details navigation is blocked when session is scoped to another device", %{conn: conn} do
      allowed = create_device!(%{mac_address: "DE:AD:BE:EF:00:03"})
      blocked = create_device!(%{mac_address: "DE:AD:BE:EF:00:04"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "device_id" => allowed.id})

      {:ok, view, _html} = live(conn, ~p"/devices")

      assert render(view) =~ allowed.mac_address
      refute render(view) =~ blocked.mac_address
    end

    test "device details navigation is blocked when scoped device list is empty", %{conn: conn} do
      device = create_device!(%{mac_address: "DE:AD:BE:EF:00:05"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "device_ids" => []})

      {:ok, view, _html} = live(conn, ~p"/devices")

      refute render(view) =~ device.mac_address
    end

    test "scoped manage permissions only allow visible authorized devices", %{conn: conn} do
      allowed = create_device!(%{mac_address: "DE:AD:BE:EF:00:09", approval_status: :pending})
      blocked = create_device!(%{mac_address: "DE:AD:BE:EF:00:0A", approval_status: :pending})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => true, "can_manage" => true, "device_ids" => [allowed.id]})

      {:ok, view, _html} = live(conn, ~p"/devices")

      assert render(view) =~ allowed.mac_address
      refute render(view) =~ blocked.mac_address

      render_hook(view, "toggle_selection", %{"id" => blocked.id})
      assert render(view) =~ "not authorized to manage this device"

      view
      |> element("input[type='checkbox'][phx-value-id='#{allowed.id}']")
      |> render_click()

      view
      |> element("button[phx-click='bulk_approve']", "Approve")
      |> render_click()

      assert Devices.get_device!(allowed.id).approval_status == :approved
      assert Devices.get_device!(blocked.id).approval_status == :pending
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

    test "rejects device detail access when permissions explicitly deny access", %{conn: conn} do
      device = create_device!(%{mac_address: "E0:E0:E0:E0:E0:E1"})

      conn =
        conn
        |> init_test_session(%{})
        |> put_session("device_permissions", %{"can_view" => false})

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

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      %{remote_access_lease_ref: lease_ref, ssh_token: session_ref} = :sys.get_state(view.pid).socket.assigns
      send(view.pid, {:remote_access_lease_expired, lease_ref})

      assert render(view) =~ "Remote access session expired"
      assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, device.id)
      assert Devices.get_device!(device.id).remote_access_requested == false
    end

    test "owner death clears remote access lease", %{conn: conn} do
      device = create_device!(%{mac_address: "E3:E3:E3:E3:E3:E3"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      assert Devices.get_device!(device.id).remote_access_requested == true

      Sandbox.allow(Repo, self(), Process.whereis(RemoteAccessLeases))

      ref = Process.monitor(view.pid)
      GenServer.stop(view.pid)
      assert_receive {:DOWN, ^ref, :process, _pid, _reason}
      with_log(fn -> Devices.sync_remote_access_leases() end)

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
        |> element("a[phx-value-tab='terminal']", "Terminal")
        |> render_click()

      assert html =~ ~s(id="terminal-container")
      assert html =~ ~s(data-token=)
      assert html =~ ~s(data-command-id=)

      %{ssh_authorize_command_id: command_id, terminal_socket_token: socket_token} =
        :sys.get_state(view.pid).socket.assigns

      assert is_binary(command_id)
      assert socket_token == nil

      acknowledge_ssh_authorize_command!(device.id, view)
      assert eventually_socket_token?(view)

      %{terminal_socket_token: socket_token} = :sys.get_state(view.pid).socket.assigns
      assert is_binary(socket_token)

      [command] = Nixstasis.Domain.list_pending_commands!()
      assert command.id == command_id

      assert command.command_payload["payload"] == %{
               "content_type" => "application/vnd.nixstasis.ssh-authorize+json;version=1",
               "name" => command.command_payload["payload"]["name"],
               "data" => command.command_payload["payload"]["data"]
             }

      payload_data = Jason.decode!(command.command_payload["payload"]["data"])
      assert payload_data["target_user"] == "nixstasis-support"
      assert is_integer(payload_data["ttl_seconds"])
      assert payload_data["session_ref"] == command.command_payload["payload"]["name"]

      assert {:ok, %{"device_id" => device_id}} =
               Phoenix.Token.verify(NixstasisWeb.Endpoint, "terminal_socket", socket_token, max_age: 3600)

      assert device_id == device.id
    end

    test "terminal authorized event cannot bypass device acknowledgement", %{conn: conn} do
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:EC"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      %{ssh_authorize_command_id: command_id, ssh_token: session_ref} =
        :sys.get_state(view.pid).socket.assigns

      render_hook(view, "terminal_authorized", %{"command_id" => command_id})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ssh_authorize_command_id == command_id
      assert assigns.terminal_socket_token == nil
      assert SshKeyManager.terminal_session_active?(session_ref)
    end

    test "failed device authorization never activates the terminal socket", %{conn: conn} do
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:EA"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      %{ssh_authorize_command_id: command_id, ssh_token: session_ref, terminal_socket_token: socket_token} =
        :sys.get_state(view.pid).socket.assigns

      assert is_binary(command_id)
      assert is_binary(session_ref)
      assert socket_token == nil

      loaded_device = Devices.get_device!(device.id)
      _ = Devices.pop_pending_commands(loaded_device)

      assert {:ok, 1} =
               Devices.acknowledge_command_results(loaded_device, [
                 %{"command_id" => command_id, "status" => "FAILED", "error" => "denied"}
               ])

      send(view.pid, {:terminal_authorization_check, command_id})
      assert eventually_terminal_authorization_failed?(view)
      assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, device.id)
    end

    test "authorization polling timeout clears the pending terminal session", %{conn: conn} do
      previous_timeout = Application.get_env(:nixstasis, :terminal_authorization_timeout_ms)
      previous_interval = Application.get_env(:nixstasis, :terminal_authorization_poll_interval_ms)
      Application.put_env(:nixstasis, :terminal_authorization_timeout_ms, 0)
      Application.put_env(:nixstasis, :terminal_authorization_poll_interval_ms, 0)

      on_exit(fn ->
        if is_nil(previous_timeout) do
          Application.delete_env(:nixstasis, :terminal_authorization_timeout_ms)
        else
          Application.put_env(:nixstasis, :terminal_authorization_timeout_ms, previous_timeout)
        end

        if is_nil(previous_interval) do
          Application.delete_env(:nixstasis, :terminal_authorization_poll_interval_ms)
        else
          Application.put_env(:nixstasis, :terminal_authorization_poll_interval_ms, previous_interval)
        end
      end)

      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:EB"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      %{ssh_token: session_ref} = :sys.get_state(view.pid).socket.assigns
      assert eventually_terminal_authorization_failed?(view)
      assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, device.id)
    end

    test "caps configured SSH authorization TTL at the terminal session lifetime", %{conn: conn} do
      previous_ttl = Application.get_env(:nixstasis, :ssh_authorization_ttl_seconds)

      on_exit(fn ->
        if is_nil(previous_ttl) do
          Application.delete_env(:nixstasis, :ssh_authorization_ttl_seconds)
        else
          Application.put_env(:nixstasis, :ssh_authorization_ttl_seconds, previous_ttl)
        end
      end)

      Application.put_env(:nixstasis, :ssh_authorization_ttl_seconds, 2 * 60 * 60)
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:E7"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      _html =
        view
        |> element("a[phx-value-tab='terminal']", "Terminal")
        |> render_click()

      [command] = Nixstasis.Domain.list_pending_commands!()
      payload_data = Jason.decode!(command.command_payload["payload"]["data"])
      assert payload_data["ttl_seconds"] == 60 * 60
    end

    test "rejects non-positive configured SSH authorization TTL", %{conn: conn} do
      previous_ttl = Application.get_env(:nixstasis, :ssh_authorization_ttl_seconds)

      on_exit(fn ->
        if is_nil(previous_ttl) do
          Application.delete_env(:nixstasis, :ssh_authorization_ttl_seconds)
        else
          Application.put_env(:nixstasis, :ssh_authorization_ttl_seconds, previous_ttl)
        end
      end)

      Application.put_env(:nixstasis, :ssh_authorization_ttl_seconds, 0)
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:E8"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      html =
        view
        |> element("a[phx-value-tab='terminal']", "Terminal")
        |> render_click()

      assert html =~ "Invalid SSH authorization TTL configuration"
      assert Nixstasis.Domain.list_pending_commands!() == []
    end

    test "queue failure clears a newly created terminal session", %{conn: conn} do
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:E9"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")
      before = :sys.get_state(SshKeyManager.TerminalSessions).sessions

      assert :ok = Devices.delete_device(device)

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      assert :sys.get_state(SshKeyManager.TerminalSessions).sessions == before
    end

    test "terminal close clears consumed session assigns", %{conn: conn} do
      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:E6"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      %{ssh_token: token} = :sys.get_state(view.pid).socket.assigns

      render_hook(view, "terminal_closed", %{"token" => token})

      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.ssh_session_started
      assert assigns.terminal_closed?
      assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(token, device.id)

      revoke_count =
        Domain.list_pending_commands!()
        |> Enum.count(&(&1.command_payload["type"] == "ssh_revoke"))

      assert revoke_count == 1
      assert assigns.ssh_authorize_command_id == nil
      assert assigns.terminal_socket_token == nil

      html = render(view)
      assert html =~ ~s(id="terminal-container")
      assert html =~ ~s(data-closed="true")
      assert html =~ "Terminal session ended"
      assert has_element?(view, "button[phx-click='retry_session'][aria-label='Restart session']")
    end

    test "terminal journey launches, runs commands, closes, and reopens", %{conn: conn} do
      previous = Application.get_env(:nixstasis, :terminal_ssh_client)
      Application.put_env(:nixstasis, :terminal_ssh_client, TerminalJourneySshClient)

      on_exit(fn ->
        if previous do
          Application.put_env(:nixstasis, :terminal_ssh_client, previous)
        else
          Application.delete_env(:nixstasis, :terminal_ssh_client)
        end
      end)

      device = create_device!(%{mac_address: "E4:E4:E4:E4:E4:E5"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      first_socket = start_terminal_from_view(view, device.id)
      first_session_ref = terminal_session_ref(view)
      Phoenix.ChannelTest.push(first_socket, "input", %{"data" => "printf nixstasis-smoke\n"})
      assert_push("output", %{data: "nixstasis-smoke"})

      html = render_hook(view, "close_remote_access", %{})
      refute html =~ ~s(id="terminal-container")
      assert html =~ "Opening remote session"
      assert Devices.get_device!(device.id).remote_access_requested == false

      view
      |> element("button[phx-click='retry_session'][aria-label='Restart session']")
      |> render_click()

      assert Devices.get_device!(device.id).remote_access_requested == true

      view
      |> element("a[phx-value-tab='terminal']", "Terminal")
      |> render_click()

      second_socket = start_terminal_from_view(view, device.id)
      refute terminal_session_ref(view) == first_session_ref
      Phoenix.ChannelTest.push(second_socket, "input", %{"data" => "whoami\n"})
      assert_push("output", %{data: "nixstasis-support\n"})
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
        |> element("a[phx-value-tab='terminal']", "Terminal")
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
        |> element("a[phx-value-tab='terminal']", "Terminal")
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

      assert eventually_rendered?(view, ~s|id="pcp-chart"|)
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

    test "offline transition clears the active terminal session", %{conn: conn} do
      device = create_device!(%{mac_address: "E7:E7:E7:E7:E7:E8"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")
      _ = view |> element("a[phx-value-tab='terminal']", "Terminal") |> render_click()

      %{ssh_token: session_ref} = :sys.get_state(view.pid).socket.assigns
      {:ok, loaded_device} = Devices.get_device(device.id)

      {:ok, _updated} =
        Devices.update_device(loaded_device, %{last_seen_at: DateTime.add(DateTime.utc_now(), -10, :minute)})

      assert eventually_rendered?(view, "Device Offline")
      assert {:error, :not_found} = SshKeyManager.fetch_terminal_session(session_ref, device.id)
    end

    test "redirects with flash for missing device", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/devices", flash: %{"error" => "Device not found or unavailable"}}}} =
               live(conn, ~p"/devices/non-existent-id")
    end

    test "retry session reinitializes in place", %{conn: conn} do
      device = create_device!(%{mac_address: "FA:FA:FA:FA:FA:FA"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("button[phx-click='retry_session'][aria-label='Restart session']")
      |> render_click()

      assert render(view) =~ "Session reinitialized"
      assert render(view) =~ "Cockpit"
      assert render(view) =~ "Performance History"
      assert render(view) =~ "Remote Terminal"
    end

    test "PCP tab renders persisted PCP telemetry samples", %{conn: conn} do
      device = create_device!(%{mac_address: "FA:FA:FA:FA:FA:FB"})

      {:ok, _event} =
        Nixstasis.Domain.create_telemetry_event(%{
          device_id: device.id,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          payload: %{
            "scripts" => %{
              "pcp" => %{
                "data" => %{
                  "output" => %{
                    "load_1m" => 1.25,
                    "memory_used" => 4_547_452,
                    "memory_used_pct" => 55.96,
                    "disk_full_pct" => 2.75
                  }
                }
              }
            }
          }
        })

      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      html =
        view
        |> element("a[phx-value-tab='pcp']", "Performance History")
        |> render_click()

      assert html =~ "PCP Metrics"
      assert html =~ "phx-update=\"ignore\""
      assert html =~ "Load 1m"
      assert html =~ "55.96"
      assert html =~ "2.75"
    end

    test "PCP tab refreshes when new heartbeat telemetry arrives", %{conn: conn} do
      device = create_device!(%{mac_address: "FA:FA:FA:FA:FA:FC"})
      {:ok, view, _html} = live(conn, ~p"/devices/#{device.id}")

      view
      |> element("a[phx-value-tab='pcp']", "Performance History")
      |> render_click()

      {:ok, _event} =
        Nixstasis.Domain.create_telemetry_event(%{
          device_id: device.id,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          payload: %{
            "scripts" => %{
              "pcp" => %{
                "data" => %{
                  "output" => %{
                    "load_1m" => 0.75,
                    "memory_used" => 1_234_567,
                    "memory_used_pct" => 15.19,
                    "disk_full_pct" => 4.5
                  }
                }
              }
            }
          }
        })

      send(view.pid, {:device_last_seen_updated, %{id: device.id}})

      assert eventually_rendered?(view, "15.19")
      assert render(view) =~ "4.5"
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

  defp eventually_cleared?(view, attempts \\ 20)

  defp eventually_cleared?(view, attempts) when attempts > 0 do
    if render(view) =~ "Device created successfully" do
      Process.sleep(5)
      eventually_cleared?(view, attempts - 1)
    else
      true
    end
  end

  defp eventually_cleared?(_view, 0), do: false

  defp start_terminal_from_view(view, device_id) do
    view
    |> element("a[phx-value-tab='terminal']", "Terminal")
    |> render_click()

    %{ssh_token: session_ref} = :sys.get_state(view.pid).socket.assigns

    acknowledge_ssh_authorize_command!(device_id, view)
    %{ssh_authorize_command_id: command_id} = :sys.get_state(view.pid).socket.assigns

    assert {:ok, _, socket} =
             NixstasisWeb.UserSocket
             |> socket("user_id", %{terminal_device_id: device_id})
             |> subscribe_and_join(NixstasisWeb.TerminalChannel, "terminal:#{device_id}", %{
               "token" => session_ref,
               "command_id" => command_id
             })

    socket
  end

  defp terminal_session_ref(view) do
    %{ssh_token: session_ref} = :sys.get_state(view.pid).socket.assigns
    session_ref
  end

  defp acknowledge_ssh_authorize_command!(device_id, view) do
    %{ssh_authorize_command_id: command_id} = :sys.get_state(view.pid).socket.assigns
    device = Devices.get_device!(device_id)
    _ = Devices.pop_pending_commands(device)

    assert {:ok, 1} =
             Devices.acknowledge_command_results(device, [
               %{"command_id" => command_id, "status" => "OK", "output" => %{}}
             ])

    send(view.pid, {:terminal_authorization_check, command_id})
    assert eventually_socket_token?(view)
  end

  defp eventually_socket_token?(view, attempts \\ 20)

  defp eventually_socket_token?(view, attempts) when attempts > 0 do
    if is_binary(:sys.get_state(view.pid).socket.assigns[:terminal_socket_token]) do
      true
    else
      Process.sleep(5)
      eventually_socket_token?(view, attempts - 1)
    end
  end

  defp eventually_socket_token?(_view, 0), do: false

  defp eventually_terminal_authorization_failed?(view, attempts \\ 20)

  defp eventually_terminal_authorization_failed?(view, attempts) when attempts > 0 do
    assigns = :sys.get_state(view.pid).socket.assigns

    if assigns.ssh_session_started == false and assigns.terminal_socket_token == nil and assigns.terminal_closed? do
      true
    else
      Process.sleep(5)
      eventually_terminal_authorization_failed?(view, attempts - 1)
    end
  end

  defp eventually_terminal_authorization_failed?(_view, 0), do: false
end
