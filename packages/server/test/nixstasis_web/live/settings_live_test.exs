defmodule NixstasisWeb.SettingsLiveTest do
  use NixstasisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Nixstasis.Settings

  setup %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{})
      |> put_session("settings_permissions", %{"can_manage" => true})

    {:ok, conn: conn}
  end

  test "viewer sessions cannot open settings", %{conn: conn} do
    conn = put_session(conn, "settings_permissions", %{"can_manage" => false})

    assert {:error, {:live_redirect, %{to: "/", flash: %{"error" => message}}}} =
             live(conn, ~p"/settings")

    assert message =~ "Not authorized"
  end

  test "stored webhook secrets are not rendered", %{conn: conn} do
    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "email" => "alerts@example.com",
               "webhook_url" => "https://hooks.example.invalid/alert?token=stored-secret"
             })

    {:ok, _view, html} = live(conn, ~p"/settings")

    assert html =~ "A webhook is configured"
    refute html =~ "stored-secret"
    refute html =~ "hooks.example.invalid"
  end

  test "private webhook destinations are rejected without replacing the stored value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    render_submit(element(view, "#notification-settings-form"), %{
      "email" => "alerts@example.com",
      "webhook_url" => "https://169.254.169.254/latest/meta-data",
      "clear_webhook_url" => "false"
    })

    assert render(view) =~ "Webhook URL must use HTTPS and resolve only to public network addresses"
    assert Settings.get_notifications_config()["webhook_url"] == nil
  end

  test "admin can explicitly clear a configured webhook without revealing it", %{conn: conn} do
    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "email" => "alerts@example.com",
               "webhook_url" => "https://hooks.example.invalid/alert?token=stored-secret"
             })

    {:ok, view, _html} = live(conn, ~p"/settings")

    render_submit(element(view, "#notification-settings-form"), %{
      "email" => "alerts@example.com",
      "webhook_url" => "",
      "clear_webhook_url" => "true"
    })

    assert render(view) =~ "Notification settings updated"
    assert Settings.get_notifications_config()["webhook_url"] == nil
  end
end
