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

  test "create form validates and saves command entry", %{conn: conn} do
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
  end
end
