defmodule NixstasisWeb.ReportsLiveTest do
  use NixstasisWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Nixstasis.Devices
  alias Nixstasis.Monitoring.Telemetry
  alias Nixstasis.Repo
  alias Nixstasis.Reporting

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:41",
        "product_name" => "report-schema-product",
        "schema" => %{
          "product" => "report-schema-product",
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
          "product" => "report-schema-product-2",
          "version" => "v1",
          "properties" => %{
            "battery" => %{"type" => "number"}
          }
        }
      })

    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:43",
        "product_name" => "report-schema-product",
        "schema" => %{
          "product" => "report-schema-product",
          "version" => "v2",
          "properties" => %{
            "pressure" => %{"type" => "number"}
          }
        }
      })

    :ok
  end

  test "new report modal renders all-schema selectors and options", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/reports/new")

    assert html =~ "Script Schema"
    assert html =~ "Limits columns to fields in the selected script."
    assert html =~ "Schema Version"
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
    assert html =~ "Schema Version"
  end

  test "malformed schema field payload does not crash live component", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reports/new")

    html =
      view
      |> element("select[phx-change='update_field']")
      |> render_change(%{"_target" => ["value"], "value" => "value=battery"})

    assert html =~ "Script Schema"
    assert html =~ "Schema Version"
  end

  test "explicit schema version selection drives report schema options", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    html =
      view
      |> element("#report-schema-id")
      |> render_change(%{"schema_id" => "report-schema-product"})

    assert html =~ "report-schema-version"

    html =
      view
      |> element("#report-schema-version")
      |> render_change(%{"schema_version" => "v2"})

    assert html =~ "Pressure"
    assert html =~ "<option value=\"pressure\">Pressure</option>"
    refute html =~ "<option value=\"temp\">Temp</option>"

    html =
      view
      |> element("select[id='report-field-path-#{field_id}']")
      |> render_change(%{
        "_target" => ["fields", field_id, "path"],
        "fields" => %{field_id => %{"path" => "pressure"}}
      })

    assert html =~ "Pressure"
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

  test "reports index uses report title as primary view link and icon-only secondary actions", %{
    conn: conn
  } do
    report_a =
      report_fixture(%{
        "name" => "Alpha Report",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    _report_b =
      report_fixture(%{
        "name" => "Beta Report",
        "config" => %{"source" => "e2e", "fields" => [%{"path" => "status"}], "filters" => []}
      })

    {:ok, _view, html} = live(conn, ~p"/reports")

    assert html =~ "aria-label=\"Edit report Alpha Report\""
    assert html =~ "aria-label=\"Delete report Alpha Report\""
    assert html =~ report_a.name
    assert html =~ "/reports/#{report_a.id}\""
  end

  test "reports index filters by fuzzy name and selected schema-field chips", %{conn: conn} do
    _cpu =
      report_fixture(%{
        "name" => "CPU Health",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "cpu.usage"}],
          "filters" => []
        }
      })

    _temp =
      report_fixture(%{
        "name" => "Temp Trends",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    {:ok, _view, html} = live(conn, ~p"/reports?filters[name]=hea")
    assert html =~ "CPU Health"
    refute html =~ "Temp Trends"

    {:ok, _view, html2} = live(conn, ~p"/reports?filters[field_queries][]=cpu.usage")
    assert html2 =~ "CPU Health"
    refute html2 =~ "Temp Trends"
  end

  test "schema-field filter supports multiple selections and ignores duplicates", %{conn: conn} do
    _temp_humidity =
      report_fixture(%{
        "name" => "Temp and Humidity",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp"}, %{"path" => "humidity"}],
          "filters" => []
        }
      })

    _temp_only =
      report_fixture(%{
        "name" => "Temp Only",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    {:ok, view, html} = live(conn, ~p"/reports")
    assert html =~ "Temp and Humidity"
    assert html =~ "Temp Only"

    _html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "temp"})

    html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "humidity"})

    assert html =~ "Temp and Humidity"
    refute html =~ "Temp Only"

    html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "temp"})

    assert html =~ "Temp and Humidity"
    assert html =~ "phx-value-field=\"temp\""
  end

  test "removing and clearing schema-field chips fully resets filter state", %{conn: conn} do
    _temp_humidity =
      report_fixture(%{
        "name" => "Temp and Humidity Reset",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp"}, %{"path" => "humidity"}],
          "filters" => []
        }
      })

    _temp_only =
      report_fixture(%{
        "name" => "Temp Only Reset",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    {:ok, view, _html} = live(conn, ~p"/reports")

    _html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "temp"})

    html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "humidity"})

    assert html =~ "Temp and Humidity Reset"
    refute html =~ "Temp Only Reset"

    html =
      view
      |> element("button[phx-click='remove_field_filter'][phx-value-field='humidity']")
      |> render_click()

    assert html =~ "Temp and Humidity Reset"
    assert html =~ "Temp Only Reset"

    _html =
      view
      |> element("button[phx-click='remove_field_filter'][phx-value-field='temp']")
      |> render_click()

    html =
      view
      |> element("button[phx-click='clear_filters']")
      |> render_click()

    assert html =~ "Temp and Humidity Reset"
    assert html =~ "Temp Only Reset"
  end

  test "field dropdown selection adds chip immediately", %{conn: conn} do
    _temp =
      report_fixture(%{
        "name" => "Temp Autocomplete",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    _humidity =
      report_fixture(%{
        "name" => "Humidity Autocomplete",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "humidity"}],
          "filters" => []
        }
      })

    {:ok, view, _html} = live(conn, ~p"/reports")

    html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "temp"})

    assert html =~ "Temp Autocomplete"
    refute html =~ "Humidity Autocomplete"

    _html =
      view
      |> element("button[phx-click='remove_field_filter'][phx-value-field='temp']")
      |> render_click()

    html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "humidity"})

    assert html =~ "Humidity Autocomplete"
    refute html =~ "Temp Autocomplete"
  end

  test "selected field is removed from dropdown options and cannot duplicate chip", %{conn: conn} do
    _temp =
      report_fixture(%{
        "name" => "Temp No Duplicate",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    {:ok, view, _html} = live(conn, ~p"/reports")

    html =
      view
      |> element("form[phx-change='add_field_filter_select']")
      |> render_change(%{"field" => "temp"})

    assert html =~ "Temp No Duplicate"
    refute html =~ "<option value=\"temp\">"

    occurrences =
      Regex.scan(~r/phx-click="remove_field_filter" phx-value-field="temp"/, html)
      |> length()

    assert occurrences == 1
  end

  test "edit action preloads schema fields and filters from report config", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "Preloaded Report",
        "config" => %{
          "source" => "telemetry",
          "schema_id" => "report-schema-product",
          "fields" => [%{"path" => "temp", "alias" => "Temperature"}],
          "filters" => [%{"field" => "temp", "operator" => ">=", "value" => "25"}]
        }
      })

    {:ok, _view, html} = live(conn, ~p"/reports/#{report.id}/edit")

    assert html =~ "Edit Report"
    assert html =~ "Preloaded Report"
    assert html =~ "Temperature"
    assert html =~ "value=\"25\""
    assert html =~ "report-schema-product"
  end

  test "edit mode disables and de-focuses name input and focuses first column field", %{
    conn: conn
  } do
    report =
      report_fixture(%{
        "name" => "Locked Name",
        "config" => %{
          "source" => "telemetry",
          "schema_id" => "report-schema-product",
          "fields" => [%{"path" => "temp", "alias" => "Temperature"}],
          "filters" => [%{"field" => "temp", "operator" => ">=", "value" => "20"}]
        }
      })

    {:ok, view, html} = live(conn, ~p"/reports/#{report.id}/edit")
    assert html =~ "id=\"report-name-input\""
    assert html =~ "disabled"
    refute html =~ "phx-hook=\"ReportNameAutofocus\""

    assert_push_event(view, "focus_schema_field", %{id: focus_id})
    assert String.starts_with?(focus_id, "report-field-path-")

    filter_id = select_id!(html, "field")

    html =
      view
      |> element("input[id='report-filter-value-#{filter_id}']")
      |> render_change(%{
        "_target" => ["filters", filter_id, "value"],
        "filters" => %{filter_id => %{"value" => "21"}}
      })

    refute html =~ "Report title is already used."
  end

  test "editing report saves when disabled name input is not submitted", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "Schema Seed Report",
        "config" => %{
          "source" => "telemetry",
          "schema_id" => "report-schema-product",
          "fields" => [
            %{"path" => "temp", "alias" => "Temperature"},
            %{"path" => "humidity", "alias" => "Humidity"}
          ],
          "filters" => [%{"field" => "temp", "operator" => ">=", "value" => "20"}]
        }
      })

    {:ok, view, html} = live(conn, ~p"/reports/#{report.id}/edit")
    [field_a, field_b] = select_ids!(html, "path")
    [filter_id] = select_ids!(html, "field")

    html =
      view
      |> element("form#report-builder-form")
      |> render_submit(%{
        "schema_id" => "report-schema-product",
        "fields" => %{
          field_a => %{"path" => "temp", "alias" => "Temperature"},
          field_b => %{"path" => "humidity", "alias" => "Humidity Title"}
        },
        "filters" => %{
          filter_id => %{"field" => "temp", "operator" => ">=", "value" => "20"}
        }
      })

    assert is_binary(html)
    saved = Reporting.get_custom_report!(report.id)

    assert Enum.any?(saved.config["fields"], fn field ->
             field["path"] == "humidity" and field["alias"] == "Humidity Title"
           end)
  end

  test "creating report persists submitted column title without requiring blur", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/reports/new")
    field_id = select_id!(html, "path")

    _html =
      view
      |> element("form#report-builder-form")
      |> render_submit(%{
        "name" => "Alias Persist Create",
        "schema_id" => "report-schema-product",
        "fields" => %{
          field_id => %{"path" => "temp", "alias" => "Room Temperature"}
        },
        "filters" => %{}
      })

    saved =
      Reporting.list_custom_reports()
      |> Enum.find(&(&1.name == "Alias Persist Create"))

    assert saved
    assert saved.config["fields"] == [%{"path" => "temp", "alias" => "Room Temperature"}]
  end

  test "reports index delete action requires explicit confirmation", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "Delete Me",
        "config" => %{"source" => "telemetry", "fields" => [], "filters" => []}
      })

    {:ok, view, _html} = live(conn, ~p"/reports")

    html =
      view
      |> element("button[phx-click='confirm_delete'][phx-value-id='#{report.id}']")
      |> render_click()

    assert html =~ "Delete Report"
    assert html =~ "Delete Me"

    _html =
      view
      |> element("button[phx-click='cancel_delete']")
      |> render_click()

    assert Reporting.get_custom_report!(report.id)

    _html =
      view
      |> element("button[phx-click='confirm_delete'][phx-value-id='#{report.id}']")
      |> render_click()

    _html =
      view
      |> element("button[phx-click='delete_report']")
      |> render_click()

    assert_raise Ash.Error.Invalid, fn -> Reporting.get_custom_report!(report.id) end
  end

  test "report detail supports sorting and filter operators", %{conn: conn} do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:91",
        "product_name" => "report-live-results",
        "schema" => %{
          "product" => "report-live-results",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    for temp <- [15, 35, 45, 100] do
      Repo.insert!(%Telemetry{
        device_id: device.id,
        payload: %{"temp" => temp},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end

    report =
      report_fixture(%{
        "name" => "Live Report",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp", "alias" => "temp"}],
          "filters" => []
        }
      })

    {:ok, view, html} = live(conn, ~p"/reports/#{report.id}")
    assert html =~ "Live Report"
    assert html =~ "15"
    assert html =~ "35"
    assert html =~ "45"
    assert html =~ "100"

    assert ["15", "35", "45", "100"] == report_result_values(html)

    html =
      view
      |> form("form[phx-change='apply_filters']", %{
        "filter" => %{"column" => "temp", "operator" => ">", "value" => "25"}
      })
      |> render_change()

    assert html =~ "35"
    assert html =~ "45"
    assert html =~ "100"
    assert ["35", "45", "100"] == report_result_values(html)

    html =
      view
      |> element("button[phx-click='set_sort'][phx-value-by='temp']")
      |> render_click()

    assert html =~ "temp"
    assert ["35", "45", "100"] == report_result_values(html)

    html =
      view
      |> element("button[phx-click='set_sort'][phx-value-by='temp']")
      |> render_click()

    assert ["100", "45", "35"] == report_result_values(html)
  end

  test "report detail filters aliased columns by configured payload path", %{conn: conn} do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:93",
        "product_name" => "report-live-alias-filter",
        "schema" => %{
          "product" => "report-live-alias-filter",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    for temp <- [20, 80] do
      Repo.insert!(%Telemetry{
        device_id: device.id,
        payload: %{"temp" => temp},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end

    report =
      report_fixture(%{
        "name" => "Aliased Live Report",
        "config" => %{
          "source" => "telemetry",
          "schema_id" => "report-live-alias-filter",
          "fields" => [%{"path" => "temp", "alias" => "room_temp"}],
          "filters" => [%{"field" => "device_id", "operator" => "=", "value" => device.id}]
        }
      })

    {:ok, view, html} = live(conn, ~p"/reports/#{report.id}")
    assert ["20", "80"] == report_result_values(html)

    html =
      view
      |> form("form[phx-change='apply_filters']", %{
        "filter" => %{"column" => "room_temp", "operator" => ">", "value" => "50"}
      })
      |> render_change()

    assert ["80"] == report_result_values(html)
  end

  test "report detail limits database-backed result loading", %{conn: conn} do
    {:ok, device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:92",
        "product_name" => "report-live-result-limit",
        "schema" => %{
          "product" => "report-live-result-limit",
          "version" => "v1",
          "properties" => %{"temp" => %{"type" => "number"}}
        }
      })

    for temp <- 1..260 do
      Repo.insert!(%Telemetry{
        device_id: device.id,
        payload: %{"temp" => temp},
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    end

    report =
      report_fixture(%{
        "name" => "Limited Live Report",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp", "alias" => "temp"}],
          "filters" => [%{"field" => "device_id", "operator" => "=", "value" => device.id}]
        }
      })

    {:ok, _view, html} = live(conn, ~p"/reports/#{report.id}?sort_by=temp&sort_dir=asc")

    assert length(Regex.scan(~r/<tr>/, html)) <= 251
  end

  test "report detail operator list changes by selected column type", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:77",
        "product_name" => "report-schema-mixed",
        "schema" => %{
          "product" => "report-schema-mixed",
          "version" => "v1",
          "properties" => %{
            "status" => %{"type" => "string"},
            "temp" => %{"type" => "number"}
          }
        }
      })

    report =
      report_fixture(%{
        "name" => "Typed Operators",
        "config" => %{
          "source" => "telemetry",
          "schema_id" => "report-schema-mixed",
          "fields" => [
            %{"path" => "status", "alias" => "status"},
            %{"path" => "temp", "alias" => "temp"}
          ],
          "filters" => []
        }
      })

    {:ok, view, _html} = live(conn, ~p"/reports/#{report.id}")

    assert has_element?(view, "select[name='filter[operator]'] option[value='contains']")
    assert has_element?(view, "select[name='filter[operator]'] option[value=\"doesn't contain\"]")
    assert has_element?(view, "select[name='filter[operator]'] option[value='is']")
    assert has_element?(view, "select[name='filter[operator]'] option[value='is not']")
    refute has_element?(view, "select[name='filter[operator]'] option[value='>']")

    _html =
      view
      |> form("form[phx-change='apply_filters']", %{
        "filter" => %{"column" => "temp", "operator" => "is", "value" => ""}
      })
      |> render_change()

    assert has_element?(view, "select[name='filter[operator]'] option[value='>']")
    assert has_element?(view, "select[name='filter[operator]'] option[value='>=']")
    assert has_element?(view, "select[name='filter[operator]'] option[value='=']")
    assert has_element?(view, "select[name='filter[operator]'] option[value='<=']")
    assert has_element?(view, "select[name='filter[operator]'] option[value='<']")
    refute has_element?(view, "select[name='filter[operator]'] option[value='contains']")
    refute has_element?(view, "select[name='filter[operator]'] option[value=\"doesn't contain\"]")
  end

  test "unauthorized sessions cannot manage report list actions", %{conn: conn} do
    _ =
      report_fixture(%{
        "name" => "Restricted",
        "config" => %{"source" => "telemetry", "fields" => [], "filters" => []}
      })

    conn =
      conn
      |> init_test_session(%{})
      |> put_session("report_permissions", %{"can_manage" => false})

    {:ok, _view, html} = live(conn, ~p"/reports")

    refute html =~ "aria-label=\"Delete report"
    refute html =~ "aria-label=\"Edit report"
  end

  test "unauthorized sessions cannot view report detail", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "No View",
        "config" => %{"source" => "telemetry", "fields" => [], "filters" => []}
      })

    conn =
      conn |> init_test_session(%{}) |> put_session("report_permissions", %{"can_view" => false})

    assert {:error, {:live_redirect, %{to: "/reports", flash: %{"error" => message}}}} =
             live(conn, ~p"/reports/#{report.id}")

    assert message =~ "not authorized"
  end

  test "report list and detail view state restores from saved preferences", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "Preference Report",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp", "alias" => "temp"}],
          "filters" => []
        }
      })

    scoped_conn =
      conn
      |> init_test_session(%{})
      |> put_session("report_preferences", %{"kind" => "report_live", "owner" => "prefs-test"})

    {:ok, _view, _html} = live(scoped_conn, ~p"/reports?sort_by=name&sort_dir=asc&filters[name]=Preference")
    {:ok, _view, restored_list_html} = live(scoped_conn, ~p"/reports")
    assert restored_list_html =~ "Preference Report"

    {:ok, _view, _html} =
      live(
        scoped_conn,
        ~p"/reports/#{report.id}?sort_by=temp&sort_dir=desc&filter_column=temp&filter_operator=%3E&filter_value=20"
      )

    {:ok, _view, restored_detail_html} = live(scoped_conn, ~p"/reports/#{report.id}")
    assert restored_detail_html =~ "Preference Report"
    assert restored_detail_html =~ "temp"
  end

  test "report view state is not restored from csrf-only sessions", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "No CSRF Preference Report",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp", "alias" => "temp"}],
          "filters" => []
        }
      })

    csrf_conn = conn |> init_test_session(%{}) |> put_session("_csrf_token", "csrf-only")

    {:ok, _view, _html} = live(csrf_conn, ~p"/reports?sort_by=name&sort_dir=asc&filters[name]=No CSRF")
    {:ok, _view, restored_list_html} = live(csrf_conn, ~p"/reports")
    assert restored_list_html =~ "No CSRF Preference Report"

    {:ok, _view, _html} =
      live(
        csrf_conn,
        ~p"/reports/#{report.id}?sort_by=temp&sort_dir=desc&filter_column=temp&filter_operator=%3E&filter_value=20"
      )

    {:ok, _view, restored_detail_html} = live(csrf_conn, ~p"/reports/#{report.id}")
    assert restored_detail_html =~ "No CSRF Preference Report"
    assert restored_detail_html =~ "temp"
    refute restored_detail_html =~ "temp ↓"
  end

  test "invalid restored state falls back safely", %{conn: conn} do
    report =
      report_fixture(%{
        "name" => "Fallback Report",
        "config" => %{
          "source" => "telemetry",
          "fields" => [%{"path" => "temp", "alias" => "temp"}],
          "filters" => []
        }
      })

    {:ok, _view, html} =
      live(
        conn,
        ~p"/reports/#{report.id}?sort_by=bad_field&sort_dir=desc&filter_column=bad_field&filter_operator=%3C%3E&filter_value=1"
      )

    assert html =~ "Fallback Report"
    assert html =~ "temp"
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

  defp report_result_values(html) do
    ~r/<td>\s*([^<]+)\s*<\/td>/
    |> Regex.scan(html)
    |> Enum.map(fn [_, value] -> String.trim(value) end)
    |> Enum.filter(&Regex.match?(~r/^\d+(\.\d+)?$/, &1))
  end

  defp report_fixture(attrs) do
    {:ok, report} = Reporting.create_custom_report(attrs)
    report
  end
end
