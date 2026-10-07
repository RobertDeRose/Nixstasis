defmodule NixstasisWeb.SystemSettingJSONAPITest do
  use NixstasisWeb.ConnCase

  alias Nixstasis.Repo
  alias Nixstasis.Settings
  alias Nixstasis.SystemSetting

  test "POST and PATCH normalize monitoring minutes", %{conn: conn} do
    body = conn |> admin() |> create_setting("offline_window", %{"minutes" => " 25 "}) |> json_response(201)
    assert body["data"]["attributes"]["value"] == %{"minutes" => 25}

    body =
      conn
      |> admin()
      |> update_setting(body["data"]["id"], %{"minutes" => " 30 "})
      |> json_response(200)

    assert body["data"]["attributes"]["value"] == %{"minutes" => 30}
    assert Settings.get_offline_window() == 30
  end

  test "POST rejects invalid monitoring values without saving", %{conn: conn} do
    for minutes <- [0, -1, 1.5, "1.5", "25minutes", "", nil] do
      conn |> recycle() |> admin() |> create_setting("offline_window", %{"minutes" => minutes}) |> json_response(400)
      assert Settings.get_setting("offline_window") == nil
    end
  end

  test "PATCH rejects invalid monitoring values and preserves the saved window", %{conn: conn} do
    {:ok, setting} = Settings.put_setting("offline_window", %{"minutes" => 25})

    for minutes <- [0, -1, 1.5, "1.5", "25minutes", "", nil] do
      conn |> recycle() |> admin() |> update_setting(setting.id, %{"minutes" => minutes}) |> json_response(400)
      assert Settings.get_setting("offline_window") == %{"minutes" => 25}
    end
  end

  test "POST and PATCH reject unsafe webhook destinations without saving", %{conn: conn} do
    invalid_urls = ["http://93.184.216.34/alerts", "https://127.0.0.1/internal", "https://169.254.169.254/", 123]

    for url <- invalid_urls do
      conn |> recycle() |> admin() |> create_setting("notifications", %{"webhook_url" => url}) |> json_response(400)
      assert Settings.get_setting("notifications") == nil
    end

    {:ok, setting} = Settings.put_setting("notifications", %{"webhook_url" => "https://93.184.216.34/alerts"})

    for url <- invalid_urls do
      conn |> recycle() |> admin() |> update_setting(setting.id, %{"webhook_url" => url}) |> json_response(400)
      assert Settings.get_notifications_config()["webhook_url"] == "https://93.184.216.34/alerts"
    end
  end

  test "new public webhooks are normalized and JSON API null explicitly clears them", %{conn: conn} do
    body =
      conn
      |> admin()
      |> create_setting("notifications", %{
        "email" => " alerts@example.com ",
        "webhook_url" => " https://93.184.216.34/alerts "
      })
      |> json_response(201)

    assert body["data"]["attributes"]["value"] == %{
             "email" => "alerts@example.com",
             "webhook_url" => "https://93.184.216.34/alerts"
           }

    conn |> admin() |> update_setting(body["data"]["id"], %{"webhook_url" => nil}) |> json_response(200)
    assert Settings.get_notifications_config()["webhook_url"] == nil
  end

  test "unchanged legacy webhook URLs can be preserved but new private destinations cannot", %{conn: conn} do
    legacy_url = "https://hooks.example.invalid/alerts"

    setting =
      Repo.insert!(%SystemSetting{
        id: Ecto.UUID.generate(),
        key: "notifications",
        value: %{"webhook_url" => legacy_url}
      })

    conn
    |> admin()
    |> update_setting(setting.id, %{"email" => "alerts@example.com", "webhook_url" => legacy_url})
    |> json_response(200)

    assert Settings.get_notifications_config()["webhook_url"] == legacy_url

    conn
    |> admin()
    |> update_setting(setting.id, %{"webhook_url" => "https://10.0.0.1/alerts"})
    |> json_response(400)

    assert Settings.get_notifications_config()["webhook_url"] == legacy_url
  end

  test "operator roles cannot mutate global settings", %{conn: conn} do
    conn
    |> admin()
    |> put_req_header("x-token-user-roles", "nixstasis/operator")
    |> create_setting("offline_window", %{"minutes" => 25})
    |> json_response(403)

    assert Settings.get_setting("offline_window") == nil
  end

  defp admin(conn) do
    conn
    |> put_req_header("accept", "application/vnd.api+json")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> put_req_header("x-token-user-roles", "nixstasis/admin")
    |> put_trusted_proxy_auth()
  end

  defp create_setting(conn, key, value) do
    post(conn, "/api/json/system_settings", %{
      "data" => %{"type" => "system_setting", "attributes" => %{"key" => key, "value" => value}}
    })
  end

  defp update_setting(conn, id, value) do
    patch(conn, "/api/json/system_settings/#{id}", %{
      "data" => %{"type" => "system_setting", "id" => id, "attributes" => %{"value" => value}}
    })
  end
end
