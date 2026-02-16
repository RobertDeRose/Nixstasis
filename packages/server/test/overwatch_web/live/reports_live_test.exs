defmodule NixstasisWeb.ReportsLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Nixstasis.Devices

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:41",
        "product_name" => "report-schema-product",
        "schema" => %{
          "version" => "v1",
          "properties" => %{
            "temp" => %{"type" => "number"},
            "humidity" => %{"type" => "number"}
          }
        }
      })

    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:42",
        "product_name" => "report-schema-product-2",
        "schema" => %{
          "version" => "v1",
          "properties" => %{
            "battery" => %{"type" => "number"}
          }
        }
      })

    :ok
  end

  test "new report modal renders all-schema selectors and options", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/reports/new")

    assert html =~ "Script Schema"
    assert html =~ "Limits columns to fields in the selected script."
    refute html =~ "Schema Version"
    assert html =~ "All Script Schemas"
    assert html =~ "report-schema-product"
    assert html =~ "report-schema-product-2"
    assert html =~ "Temp"
    assert html =~ "Battery"
    assert html =~ "Using common script fields across all products."
  end

  test "schema field selection does not crash live component", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    html =
      view
      |> element("select[id='report-field-path-#{field_id}']")
      |> render_change(%{
        "_target" => ["fields", field_id, "path"],
        "fields" => %{field_id => %{"path" => "temp"}}
      })

    assert html =~ "Script Schema"
    refute html =~ "Schema Version"
  end

  test "malformed schema field payload does not crash live component", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("select[phx-change='update_field']")
      |> render_change(%{"_target" => ["value"], "value" => "value=battery"})

    assert html =~ "Script Schema"
    refute html =~ "Schema Version"
  end

  test "changing schema product does not show cleared-selection warning", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    _html =
      view
      |> element("select[id='report-field-path-#{field_id}']")
      |> render_change(%{
        "_target" => ["fields", field_id, "path"],
        "fields" => %{field_id => %{"path" => "battery"}}
      })

    html =
      view
      |> element("#report-schema-id")
      |> render_change(%{"schema_id" => "report-schema-product"})

    refute html =~ "Schema scope changed: some selections were cleared and require reselection."
    assert html =~ "Scope limited to report-schema-product."
  end

  test "schema field selection sets default title and pushes focus to title input", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")
    expected_focus_id = "report-field-alias-" <> field_id

    html =
      view
      |> element("select[id='report-field-path-#{field_id}']")
      |> render_change(%{
        "_target" => ["fields", field_id, "path"],
        "fields" => %{field_id => %{"path" => "temp"}}
      })

    assert_push_event(view, "focus_column_title", %{id: ^expected_focus_id})
    assert alias_input_value!(html, field_id) == "Temp"

    _html =
      view
      |> element("input[id='report-field-alias-#{field_id}']")
      |> render_blur(%{"id" => field_id, "key" => "alias", "value" => "Room Temp"})

    html =
      view
      |> element("select[id='report-field-path-#{field_id}']")
      |> render_change(%{
        "_target" => ["fields", field_id, "path"],
        "fields" => %{field_id => %{"path" => "humidity"}}
      })

    assert_push_event(view, "focus_column_title", %{id: ^expected_focus_id})
    assert alias_input_value!(html, field_id) == "Humidity"
  end

  test "cannot delete the last remaining column", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    refute has_element?(view, "button[phx-click='remove_field']")

    html =
      view
      |> element("button[phx-click='add_field']")
      |> render_click()

    [_, remove_id] = select_ids!(html, "path")

    assert has_element?(view, "button[phx-click='remove_field']")

    _html =
      view
      |> element("button[phx-click='remove_field'][phx-value-id='#{remove_id}']")
      |> render_click()

    refute has_element?(view, "button[phx-click='remove_field']")
  end

  test "add column focuses schema field for the new row", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    initial_id = select_id!(html, "path")

    html =
      view
      |> element("button[phx-click='add_field']")
      |> render_click()

    [existing_id, new_id] = select_ids!(html, "path")
    assert existing_id == initial_id

    expected_focus_id = "report-field-path-" <> new_id
    assert_push_event(view, "focus_schema_field", %{id: ^expected_focus_id})
  end

  test "enter on column title adds next column and focuses its schema field", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    html =
      view
      |> element("input[id='report-field-alias-#{field_id}']")
      |> render_keydown(%{"key" => "Enter", "id" => field_id})

    [existing_id, new_id] = select_ids!(html, "path")
    assert existing_id == field_id

    expected_focus_id = "report-field-path-" <> new_id
    assert_push_event(view, "focus_schema_field", %{id: ^expected_focus_id})
  end

  test "tab on column title does not add a new column", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    html =
      view
      |> element("input[id='report-field-alias-#{field_id}']")
      |> render_keydown(%{"key" => "Tab", "id" => field_id})

    assert [field_id] == select_ids!(html, "path")
  end

  test "delete on just-enter-created schema field removes that new column", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    initial_id = select_id!(html, "path")

    html =
      view
      |> element("input[id='report-field-alias-#{initial_id}']")
      |> render_keydown(%{"key" => "Enter", "id" => initial_id})

    [existing_id, new_id] = select_ids!(html, "path")
    assert existing_id == initial_id

    html =
      view
      |> element("select[id='report-field-path-#{new_id}']")
      |> render_keydown(%{"field_id" => new_id, "key" => "Delete"})

    expected_focus_id = "report-field-alias-" <> existing_id
    assert_push_event(view, "focus_column_title", %{id: ^expected_focus_id})
    assert [existing_id] == select_ids!(html, "path")
  end

  test "delete on existing schema field removes row even when not newly added", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    first_id = select_id!(html, "path")

    html =
      view
      |> element("button[phx-click='add_field']")
      |> render_click()

    [kept_id, second_id] = select_ids!(html, "path")
    assert kept_id == first_id

    html =
      view
      |> element("select[id='report-field-path-#{first_id}']")
      |> render_keydown(%{"field_id" => first_id, "key" => "Delete"})

    expected_focus_id = "report-field-alias-" <> second_id
    assert_push_event(view, "focus_column_title", %{id: ^expected_focus_id})
    assert [second_id] == select_ids!(html, "path")
  end

  test "filter value label shows type after schema field is selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    html =
      view
      |> element("select[id='report-filter-field-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "field"],
        "filters" => %{filter_id => %{"field" => "temp"}}
      })

    assert html =~ "Value (number)"
  end

  test "selecting filter field focuses operator, then operator focuses value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    _html =
      view
      |> element("select[id='report-filter-field-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "field"],
        "filters" => %{filter_id => %{"field" => "temp"}}
      })

    expected_operator_id = "report-filter-operator-" <> filter_id
    assert_push_event(view, "focus_filter_operator", %{id: ^expected_operator_id})

    _html =
      view
      |> element("select[id='report-filter-operator-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "operator"],
        "filters" => %{filter_id => %{"operator" => "!="}}
      })

    expected_value_id = "report-filter-value-" <> filter_id
    assert_push_event(view, "focus_filter_value", %{id: ^expected_value_id})
  end

  test "enter on filter value adds another filter and focuses new schema field", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    html =
      view
      |> element("input[id='report-filter-value-#{filter_id}']")
      |> render_keydown(%{"key" => "Enter", "id" => filter_id})

    [existing_id, new_id] = select_ids!(html, "field")
    assert existing_id == filter_id

    expected_field_id = "report-filter-field-" <> new_id
    assert_push_event(view, "focus_filter_field", %{id: ^expected_field_id})
  end

  test "add filter focuses schema field for the new row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")
    expected_field_id = "report-filter-field-" <> filter_id
    assert_push_event(view, "focus_filter_field", %{id: ^expected_field_id})
  end

  test "delete on filter schema field removes that filter row", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    html =
      view
      |> element("select[id='report-filter-field-#{filter_id}']")
      |> render_keydown(%{"filter_id" => filter_id, "key" => "Delete"})

    [last_field_id] = select_ids!(html, "path")
    expected_focus_id = "report-field-alias-" <> last_field_id
    assert_push_event(view, "focus_column_title", %{id: ^expected_focus_id})
    assert select_ids(html, "field") == []
  end

  test "deleting a filter focuses previous filter value", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    first_filter_id = select_id!(html, "field")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    [kept_id, removed_id] = select_ids!(html, "field")
    assert kept_id == first_filter_id

    html =
      view
      |> element("button[phx-click='remove_filter'][phx-value-id='#{removed_id}']")
      |> render_click()

    expected_focus_id = "report-filter-value-" <> kept_id
    assert_push_event(view, "focus_filter_value", %{id: ^expected_focus_id})
    assert [kept_id] == select_ids!(html, "field")
  end

  test "deleting first filter keeps focus in filters when another remains", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    first_filter_id = select_id!(html, "field")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    [first_id, second_id] = select_ids!(html, "field")
    assert first_id == first_filter_id

    html =
      view
      |> element("button[phx-click='remove_filter'][phx-value-id='#{first_id}']")
      |> render_click()

    expected_focus_id = "report-filter-value-" <> second_id
    assert_push_event(view, "focus_filter_value", %{id: ^expected_focus_id})
    assert [second_id] == select_ids!(html, "field")
  end

  test "hidden filter field shows add-as-column action", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    html =
      view
      |> element("select[id='report-filter-field-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "field"],
        "filters" => %{filter_id => %{"field" => "temp"}}
      })

    assert html =~ "Filtered by hidden field."

    assert has_element?(
             view,
             "button[phx-click='add_filter_field_as_column'][phx-value-filter_id='#{filter_id}']"
           )

    html =
      view
      |> element("button[phx-click='add_filter_field_as_column'][phx-value-filter_id='#{filter_id}']")
      |> render_click()

    assert_push_event(view, "focus_column_title", %{id: focus_id})
    assert String.starts_with?(focus_id, "report-field-alias-")
    assert length(select_ids!(html, "path")) == 2
    assert html =~ "value=\"Temp\""
    refute html =~ "Filtered by hidden field."
  end

  test "report name uniqueness is enforced case-insensitively by backend lookup", %{conn: conn} do
    {:ok, _report} =
      Nixstasis.Reporting.create_custom_report(%{
        "name" => "Unique Report Name",
        "config" => %{"source" => "telemetry", "fields" => [], "filters" => []}
      })

    {:ok, view, _html} = live(conn, ~p"/reports/new")

    _html =
      view
      |> element("form#report-builder-form")
      |> render_change(%{"name" => "unique report name"})

    assert has_element?(view, "p.text-error", "Report title is already used.")
  end

  test "filter value validates against schema type", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    _html =
      view
      |> element("select[id='report-filter-field-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "field"],
        "filters" => %{filter_id => %{"field" => "temp"}}
      })

    html =
      view
      |> element("input[id='report-filter-value-#{filter_id}']")
      |> render_blur(%{"id" => filter_id, "key" => "value", "value" => "abc"})

    assert html =~ "Expected numeric value."
    assert html =~ "report-save-report"
    assert html =~ "disabled"
  end

  test "save enables immediately when filter value becomes valid", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    _html =
      view
      |> element("form#report-builder-form")
      |> render_change(%{"name" => "Valid Filter Save"})

    _html =
      view
      |> element("select[id='report-field-path-#{field_id}']")
      |> render_change(%{
        "_target" => ["fields", field_id, "path"],
        "fields" => %{field_id => %{"path" => "temp"}}
      })

    html =
      view
      |> element("button[phx-click='add_filter']")
      |> render_click()

    filter_id = select_id!(html, "field")

    _html =
      view
      |> element("select[id='report-filter-field-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "field"],
        "filters" => %{filter_id => %{"field" => "temp"}}
      })

    assert has_element?(view, "#report-save-report[disabled]")

    _html =
      view
      |> element("input[id='report-filter-value-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "value"],
        "filters" => %{filter_id => %{"value" => "42.5"}}
      })

    refute has_element?(view, "#report-save-report[disabled]")
  end

  defp select_id!(html, key) do
    [id | _] = select_ids!(html, key)
    id
  end

  defp select_ids!(html, key) do
    ids = select_ids(html, key)

    if ids != [] do
      ids
    else
      flunk("expected a schema select with phx-value-key=#{inspect(key)}")
    end
  end

  defp select_ids(html, key) do
    escaped_key = Regex.escape(key)
    tag_regex = ~r/<select[^>]*name="(?:fields|filters)\[[^"]+\]\[#{escaped_key}\]"[^>]*>/

    tag_regex
    |> Regex.scan(html)
    |> Enum.map(fn [tag | _] -> tag end)
    |> Enum.map(fn tag ->
      case Regex.run(~r/name="(?:fields|filters)\[([^\]]+)\]\[#{escaped_key}\]"/, tag) do
        [_, id] -> id
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp alias_input_value!(html, field_id) do
    escaped_id = Regex.escape(field_id)

    tag_regex =
      ~r/<input[^>]*id="report-field-alias-#{escaped_id}"[^>]*>/

    with [[tag | _] | _] <- Regex.scan(tag_regex, html),
         [_, value] <- Regex.run(~r/value="([^"]*)"/, tag) do
      value
    else
      _ -> flunk("expected alias input for field id #{inspect(field_id)}")
    end
  end
end
