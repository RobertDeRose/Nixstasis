defmodule NixstasisWeb.SettingsLiveTest do
  use NixstasisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Nixstasis.Settings
  alias NixstasisWeb.SettingsLive

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

  test "admin monitoring updates persist normalized minutes across reloads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    render_submit(element(view, "#monitoring-settings-form"), %{"minutes" => "25"})

    assert has_element?(view, "#flash-info", "Monitoring settings updated")
    assert Settings.get_setting("offline_window") == %{"minutes" => 25}

    {:ok, reloaded, _html} = live(conn, ~p"/settings")
    assert has_element?(reloaded, "#monitoring-settings-form input[name=minutes][value='25']")
  end

  test "monitoring feedback reflects the latest save attempt", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    render_submit(element(view, "#monitoring-settings-form"), %{"minutes" => "25"})
    assert has_element?(view, "#flash-info", "Monitoring settings updated")

    render_submit(element(view, "#monitoring-settings-form"), %{"minutes" => "0"})
    assert has_element?(view, "#flash-error", "Unable to update monitoring settings")
    refute has_element?(view, "#flash-info", "Monitoring settings updated")
    assert Settings.get_offline_window() == 25

    render_submit(element(view, "#monitoring-settings-form"), %{"minutes" => "30"})
    assert has_element?(view, "#flash-info", "Monitoring settings updated")
    refute has_element?(view, "#flash-error", "Unable to update monitoring settings")
    assert Settings.get_offline_window() == 30
  end

  for minutes <- ["0", "-5", "1.5", ""] do
    test "invalid monitoring minutes #{inspect(minutes)} do not overwrite settings or report success", %{conn: conn} do
      assert {:ok, _setting} = Settings.put_offline_window(%{"can_manage" => true}, 25)
      {:ok, view, _html} = live(conn, ~p"/settings")

      render_submit(element(view, "#monitoring-settings-form"), %{"minutes" => unquote(minutes)})

      assert has_element?(view, "#flash-error", "Unable to update monitoring settings")
      refute has_element?(view, "#flash-info", "Monitoring settings updated")
      assert Settings.get_offline_window() == 25

      {:ok, reloaded, _html} = live(conn, ~p"/settings")
      assert has_element?(reloaded, "#monitoring-settings-form input[name=minutes][value='25']")
    end
  end

  test "generic notification errors replace earlier success feedback" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}}
    }

    {:ok, socket} = SettingsLive.mount(%{}, %{"settings_permissions" => %{"can_manage" => true}}, socket)
    params = %{"email" => "alerts@example.com", "webhook_url" => "", "clear_webhook_url" => "false"}

    {:noreply, socket} = SettingsLive.handle_event("save_notifications", params, socket)
    assert socket.assigns.flash["info"] == "Notification settings updated"
    saved = Settings.get_notifications_config()
    form = socket.assigns.form

    # Non-map input reaches the generic error branch without mocking the context
    # or forcing a database outage. The management permission remains unchanged.
    {:noreply, socket} = SettingsLive.handle_event("save_notifications", nil, socket)
    assert socket.assigns.flash["error"] == "Unable to update notification settings"
    refute Map.has_key?(socket.assigns.flash, "info")
    assert socket.assigns.form == form
    assert Settings.get_notifications_config() == saved

    {:noreply, socket} =
      SettingsLive.handle_event("save_notifications", Map.put(params, "email", "updated@example.com"), socket)

    assert socket.assigns.flash["info"] == "Notification settings updated"
    refute Map.has_key?(socket.assigns.flash, "error")
    assert Settings.get_notifications_config()["email"] == "updated@example.com"
  end

  test "stored webhook secrets are not rendered", %{conn: conn} do
    assert {:ok, _setting} =
             Settings.put_setting("notifications", %{
               "email" => "alerts@example.com",
               "webhook_url" => "https://93.184.216.34/alert?token=stored-secret"
             })

    {:ok, _view, html} = live(conn, ~p"/settings")

    assert html =~ "A webhook is configured"
    refute html =~ "stored-secret"
    refute html =~ "93.184.216.34"
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
               "webhook_url" => "https://93.184.216.34/alert?token=stored-secret"
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
