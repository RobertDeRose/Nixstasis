defmodule NixstasisWeb.CommandPolicyLiveTest do
  use NixstasisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Nixstasis.Domain

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("command_policy_permissions", %{
        "can_view_status" => true,
        "can_view_details" => true,
        "can_manage" => true
      })
      |> put_session("device_permissions", %{"can_view" => true, "can_manage" => true})

    {:ok, network} = Domain.create_command_allowlist_category(%{slug: "network", display_name: "Network"})

    {:ok, entry} =
      Domain.create_command_allowlist_entry(%{name: "df", command_path: "/usr/bin/df", description: "Disk usage"})

    {:ok, _} = Domain.create_command_allowlist_entry_category(%{command_entry_id: entry.id, category_id: network.id})

    %{conn: conn, category: network, entry: entry}
  end

  test "lists command entries and supports category filter", %{conn: conn, category: category, entry: entry} do
    {:ok, _view, html} = live(conn, ~p"/scripts/command-policies")
    assert html =~ entry.name
    assert html =~ "Command Policies"

    {:ok, _view, filtered_html} = live(conn, ~p"/scripts/command-policies?category_id=#{category.id}")
    assert filtered_html =~ entry.name
  end

  test "redirects without command policy detail permission", %{conn: conn} do
    conn =
      put_session(conn, "command_policy_permissions", %{
        "can_view_status" => true,
        "can_view_details" => false,
        "can_manage" => false
      })

    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/scripts/command-policies")
  end

  test "assignment wizard only queues authorized approved devices", %{conn: conn, entry: entry} do
    {:ok, device} = Nixstasis.Devices.register_device(%{mac_address: "AA:BB:CC:AA:BB:01", product_name: "target"})
    {:ok, device} = Nixstasis.Devices.approve_device(device)

    {:ok, other_device} =
      Nixstasis.Devices.register_device(%{mac_address: "AA:BB:CC:AA:BB:02", product_name: "blocked"})

    {:ok, other_device} = Nixstasis.Devices.approve_device(other_device)

    conn =
      put_session(conn, "device_permissions", %{"can_view" => true, "can_manage" => true, "device_ids" => [device.id]})

    {:ok, view, html} = live(conn, ~p"/scripts/command-policies")
    assert html =~ "target"
    refute html =~ "blocked"

    view
    |> form("form[phx-submit='preview_assignment']",
      assignment: %{device_ids: [device.id], entry_ids: [entry.id], category_ids: []}
    )
    |> render_submit()

    assert render(view) =~ "Confirm and queue"
    render_click(element(view, "button", "Confirm and queue"))

    assignments = Domain.list_command_policy_assignments() |> elem(1)
    assert Enum.any?(assignments, &(&1.device_id == device.id and &1.status == :queued))
    refute Enum.any?(assignments, &(&1.device_id == other_device.id))
  end

  test "periodic refresh keeps command entry modal open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scripts/command-policies/new")

    send(view.pid, :refresh_command_policies)

    html = render(view)
    assert html =~ "New Command Entry"
    assert html =~ ~s(autocomplete="off")
    assert html =~ ~s(autocorrect="off")
  end

  test "periodic refresh keeps category modal open", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/scripts/command-policies/categories/new")

    send(view.pid, :refresh_command_policies)

    html = render(view)
    assert html =~ "New Category"
    assert html =~ ~s(autocorrect="off")
  end

  test "assignment actions are scoped to authorized devices", %{conn: conn} do
    {:ok, device} = Nixstasis.Devices.register_device(%{mac_address: "AA:BB:CC:AA:BB:03", product_name: "allowed"})
    {:ok, device} = Nixstasis.Devices.approve_device(device)

    {:ok, other_device} =
      Nixstasis.Devices.register_device(%{mac_address: "AA:BB:CC:AA:BB:04", product_name: "blocked"})

    {:ok, other_device} = Nixstasis.Devices.approve_device(other_device)

    {:ok, assignment} =
      Domain.create_command_policy_assignment(%{
        device_id: other_device.id,
        revision: 1,
        version: "policy-1",
        resolved_policy: %{"commands" => %{}}
      })

    conn =
      put_session(conn, "device_permissions", %{"can_view" => true, "can_manage" => true, "device_ids" => [device.id]})

    {:ok, view, html} = live(conn, ~p"/scripts/command-policies")

    refute html =~ other_device.id
    assert render_click(view, "retry_assignment", %{"id" => assignment.id}) =~ "Failed to resend assignment"
    assert render_click(view, "toggle_drift_warning", %{"id" => assignment.id}) =~ "Failed to update drift warning"
  end

  test "category form saves category", %{conn: conn} do
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "command_policy_audit")
    {:ok, view, _html} = live(conn, ~p"/scripts/command-policies/categories/new")

    view
    |> form("#category-form", form: %{slug: "storage", display_name: "Storage", description: "Disk commands"})
    |> render_submit()

    categories = Domain.list_command_allowlist_categories() |> elem(1)
    assert Enum.any?(categories, &(&1.slug == "storage"))
    assert_receive {:command_policy_audit, %{action: :category_created, slug: "storage"}}
  end

  test "create form validates, saves, and emits audit event", %{conn: conn} do
    Phoenix.PubSub.subscribe(Nixstasis.PubSub, "command_policy_audit")

    {:ok, view, _html} = live(conn, ~p"/scripts/command-policies/new")

    invalid_html =
      view
      |> form("#command-entry-form", form: %{name: "Bad Name", command_path: "usr/bin/df", description: "bad"})
      |> render_submit()

    refute invalid_html =~ "Command entry saved"
    refute Enum.any?(Domain.list_command_allowlist_entries() |> elem(1), &(&1.name == "Bad Name"))

    view
    |> form("#command-entry-form",
      form: %{name: "uptime", command_path: "/usr/bin/uptime", description: "Show uptime", category_ids: []}
    )
    |> render_submit()

    entries = Domain.list_command_allowlist_entries() |> elem(1)
    assert Enum.any?(entries, &(&1.name == "uptime"))
    assert_receive {:command_policy_audit, %{action: :command_entry_created, name: "uptime"}}
  end
end
