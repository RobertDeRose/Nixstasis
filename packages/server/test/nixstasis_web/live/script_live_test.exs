defmodule NixstasisWeb.ScriptLiveTest do
  use NixstasisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Nixstasis.Domain

  @endpoint NixstasisWeb.Endpoint

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("script_permissions", %{"can_view" => true, "can_manage" => true})

    {:ok, draft} =
      Domain.create_script_draft(%{
        name: "test-script",
        front_matter: %{"name" => "test-script", "schema" => %{"type" => "object"}, "version" => "1.0"},
        body: "def main():\n    return {\"ok\": true}\n"
      })

    {:ok, conn: conn, draft: draft}
  end

  describe "Script Index" do
    test "lists scripts", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/scripts")
      assert html =~ draft.name
    end

    test "shows empty state when no scripts", %{conn: conn} do
      # Delete all drafts
      Domain.list_script_drafts() |> elem(1) |> Enum.each(&Domain.destroy_script_draft/1)

      {:ok, _view, html} = live(conn, ~p"/scripts")
      assert html =~ "No scripts yet"
    end
  end

  describe "Script Show" do
    test "displays script detail", %{conn: conn, draft: draft} do
      {:ok, _view, html} = live(conn, ~p"/scripts/#{draft.id}")
      assert html =~ draft.name
      assert html =~ "Editor"
      assert html =~ "Validate"
      assert html =~ "Test"
      assert html =~ "Deploy"
    end

    test "can switch tabs", %{conn: conn, draft: draft} do
      {:ok, view, _html} = live(conn, ~p"/scripts/#{draft.id}")

      render_click(element(view, "button[phx-value-tab='validate']"))
      assert render(view) =~ "Run Validation"

      render_click(element(view, "button[phx-value-tab='test']"))
      assert render(view) =~ "Queue Test Run"

      render_click(element(view, "button[phx-value-tab='deploy']"))
      assert render(view) =~ "Deploy to Selected Devices"

      render_click(element(view, "button[phx-value-tab='history']"))
      assert render(view) =~ "Versions"
    end

    test "redirects for non-existent script", %{conn: conn} do
      {:error, {:live_redirect, %{to: "/scripts"}}} = live(conn, ~p"/scripts/non-existent-id")
    end
  end
end
