defmodule NixstasisWeb.AlertsLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Nixstasis.Devices

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:31",
        "product_name" => "alert-schema-product",
        "schema" => %{
          "version" => "v1",
          "properties" => %{
            "temp" => %{"type" => "number"},
            "status" => %{"type" => "string"}
          }
        }
      })

    :ok
  end

  test "new rule modal renders schema-driven selectors", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/alerts/new")

    assert html =~ "Schema Version"
    assert html =~ "Schema Field"
    assert html =~ "alert-schema-product"
    assert html =~ "Temp"
  end

  test "schema product/version selections persist across schema selector changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/alerts/new")

    _ =
      view
      |> element("#alert-schema-id")
      |> render_change(%{"schema_id" => "alert-schema-product"})

    assert has_element?(view, "#alert-schema-id option[value='alert-schema-product'][selected]")

    _ =
      view
      |> element("#alert-schema-version")
      |> render_change(%{"schema_version" => "v1"})

    assert has_element?(view, "#alert-schema-version option[value='v1'][selected]")

    assert has_element?(view, "#alert-schema-id option[value='alert-schema-product'][selected]")
    assert has_element?(view, "#alert-schema-version option[value='v1'][selected]")
    assert has_element?(view, "#form_condition_field option[value='temp']")
  end
end
