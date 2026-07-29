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

  test "catalog search filters catalog command options", %{conn: conn} do
    create_catalog_fixture()

    {:ok, _command} =
      Domain.create_command_catalog_command(%{
        name: "uname",
        display_name: "Kernel name",
        description: "Kernel information",
        category_slugs: [],
        active: true
      })

    {:ok, _view, html} = live(conn, ~p"/scripts/command-policies?search=disk")

    assert html =~ "df · catalog"
    refute html =~ "uname · catalog"
  end

  test "catalog preview shows per-device compatibility blockers", %{conn: conn} do
    %{command: command} = create_catalog_fixture()

    resolved = approved_device!("AA:BB:CC:AA:BC:01", "catalog-resolved")
    supported = approved_device!("AA:BB:CC:AA:BC:02", "catalog-partial")
    missing = approved_device!("AA:BB:CC:AA:BC:03", "catalog-missing")
    unsupported = approved_device!("AA:BB:CC:AA:BC:04", "catalog-unsupported")
    conflict = approved_device!("AA:BB:CC:AA:BC:05", "catalog-conflict")

    inventory!(resolved, package_installed: true, command_path: "/usr/bin/df")
    inventory!(supported, package_installed: :unknown, command_path: nil)
    inventory!(missing, package_installed: false, command_path: nil)
    inventory!(unsupported, os_release: %{"ID" => "alpine"}, package_installed: true, command_path: "/bin/df")
    inventory!(conflict, package_installed: true, command_path: "/custom/df")

    {:ok, view, html} = live(conn, ~p"/scripts/command-policies")
    assert html =~ "df · catalog"

    view
    |> form("form[phx-submit='preview_assignment']",
      assignment: %{
        device_ids: [resolved.id, supported.id, missing.id, unsupported.id, conflict.id],
        entry_ids: [],
        category_ids: [],
        catalog_command_ids: [command.id],
        catalog_category_ids: []
      }
    )
    |> render_submit()

    html = render(view)
    assert html =~ "command_path_resolved"
    assert html =~ ">supported</span>"
    assert html =~ "missing_package"
    assert html =~ "Install: apt install coreutils"
    assert html =~ "unsupported_os"
    assert html =~ "conflict"
    assert html =~ "incompatible catalog commands detected"
    refute html =~ "Confirm and queue"
  end

  test "catalog confirmation rechecks current compatibility", %{conn: conn} do
    %{command: command} = create_catalog_fixture()
    device = approved_device!("AA:BB:CC:AA:BC:08", "catalog-rechecked")
    inventory!(device, package_installed: true, command_path: "/usr/bin/df")

    {:ok, view, _html} = live(conn, ~p"/scripts/command-policies")

    view
    |> form("form[phx-submit='preview_assignment']",
      assignment: %{
        device_ids: [device.id],
        entry_ids: [],
        category_ids: [],
        catalog_command_ids: [command.id],
        catalog_category_ids: []
      }
    )
    |> render_submit()

    assert render(view) =~ "Confirm and queue"
    {:ok, _command} = Domain.update_command_catalog_command(command, %{active: false})

    assert render_click(element(view, "button", "Confirm and queue")) =~
             "Preview must be conflict-free and catalog-compatible before assignment"

    assignments = Domain.list_command_policy_assignments() |> elem(1)
    refute Enum.any?(assignments, &(&1.device_id == device.id))
  end

  test "catalog categories coexist with manual entries when queued", %{conn: conn, entry: entry} do
    %{category: category} = create_catalog_fixture()
    device = approved_device!("AA:BB:CC:AA:BC:05", "catalog-queued")
    inventory!(device, package_installed: true, command_path: "/usr/bin/df")

    {:ok, view, _html} = live(conn, ~p"/scripts/command-policies")

    view
    |> form("form[phx-submit='preview_assignment']",
      assignment: %{
        device_ids: [device.id],
        entry_ids: [entry.id],
        category_ids: [],
        catalog_command_ids: [],
        catalog_category_ids: [category.id]
      }
    )
    |> render_submit()

    assert render(view) =~ "Confirm and queue"
    render_click(element(view, "button", "Confirm and queue"))

    assignment =
      Domain.list_command_policy_assignments()
      |> elem(1)
      |> Enum.find(&(&1.device_id == device.id))

    assert assignment.resolved_policy["commands"] == %{"df" => "/usr/bin/df"}
    assert assignment.source_snapshot["entries"] == [entry.id]
    assert assignment.source_snapshot["catalog_categories"] == [category.id]

    [command] = Nixstasis.Devices.pop_pending_commands(device)
    assert command.command_payload["type"] == "apply_command_policy"
    assert command.command_payload["defer_payload"] == false
    payload = Jason.decode!(command.command_payload["payload"]["data"])
    assert payload["version"] == assignment.version
    assert payload["revision"] == assignment.revision
    assert payload["commands"] == %{"df" => "/usr/bin/df"}
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

  test "catalog preview is scoped to authorized devices", %{conn: conn} do
    %{command: command} = create_catalog_fixture()
    allowed = approved_device!("AA:BB:CC:AA:BC:06", "catalog-allowed")
    blocked = approved_device!("AA:BB:CC:AA:BC:07", "catalog-blocked")
    inventory!(allowed, package_installed: true, command_path: "/usr/bin/df")
    inventory!(blocked, package_installed: false, command_path: nil)

    conn =
      put_session(conn, "device_permissions", %{
        "can_view" => true,
        "can_manage" => true,
        "device_ids" => [allowed.id]
      })

    {:ok, view, html} = live(conn, ~p"/scripts/command-policies")
    assert html =~ "catalog-allowed"
    refute html =~ "catalog-blocked"

    render_submit(view, "preview_assignment", %{
      "assignment" => %{
        "device_ids" => [allowed.id, blocked.id],
        "entry_ids" => [],
        "category_ids" => [],
        "catalog_command_ids" => [command.id],
        "catalog_category_ids" => []
      }
    })

    html = render(view)
    assert html =~ allowed.id
    refute html =~ blocked.id
    refute html =~ "missing_package"
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

  defp create_catalog_fixture do
    {:ok, category} =
      Domain.create_command_catalog_category(%{
        slug: "diagnostics",
        display_name: "Diagnostics",
        description: "Diagnostic tools"
      })

    {:ok, command} =
      Domain.create_command_catalog_command(%{
        name: "df",
        display_name: "Disk free",
        description: "Disk usage",
        category_slugs: [category.slug],
        active: true
      })

    {:ok, _mapping} =
      Domain.create_command_catalog_mapping(%{
        catalog_command_id: command.id,
        os_family: "debian",
        package_manager: "apt",
        package_name: "coreutils",
        command_path: "/usr/bin/df",
        install_hint: "apt install coreutils"
      })

    %{category: category, command: command}
  end

  defp approved_device!(mac_address, product_name) do
    {:ok, device} = Nixstasis.Devices.register_device(%{mac_address: mac_address, product_name: product_name})
    {:ok, device} = Nixstasis.Devices.approve_device(device)
    device
  end

  defp inventory!(device, opts) do
    attrs = %{
      device_id: device.id,
      observed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      os_release: Keyword.get(opts, :os_release, %{"ID" => "debian"}),
      schema_version: 1,
      probe_catalog_version: "catalog-v1",
      architecture: "x86_64",
      package_manager: "apt",
      packages: package_evidence(Keyword.fetch!(opts, :package_installed)),
      commands: maybe_command_evidence(Keyword.get(opts, :command_path))
    }

    {:ok, snapshot} = Domain.create_device_command_inventory_snapshot(attrs)
    snapshot
  end

  defp package_evidence(:unknown), do: %{}
  defp package_evidence(installed?), do: %{"coreutils" => %{"installed" => installed?}}

  defp maybe_command_evidence(nil), do: %{}
  defp maybe_command_evidence(path), do: %{"df" => %{"path" => path}}
end
