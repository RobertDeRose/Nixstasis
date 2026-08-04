defmodule NixstasisWeb.AlertsLiveTest do
  use NixstasisWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Nixstasis.Devices
  alias Nixstasis.Domain

  @success_flash_timeout_ms 3_000

  setup do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:31",
        "product_name" => "alert-schema-product",
        "schema" => %{
          "product" => "alert-schema-product",
          "version" => "v1",
          "properties" => %{
            "temp" => %{"type" => "number"},
            "status" => %{"type" => "string"}
          }
        }
      })

    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:33",
        "product_name" => "alert-schema-product",
        "schema" => %{
          "product" => "alert-schema-product",
          "version" => "v2",
          "properties" => %{
            "pressure" => %{"type" => "number"}
          }
        }
      })

    :ok
  end

  test "new rule modal renders schema-driven selectors and action controls", %{conn: conn} do
    {:ok, view, html} = live(conn, alert_new_path())

    assert has_element?(
             view,
             "#rule-modal [role='dialog'][aria-labelledby='rule-modal-title'][aria-describedby='rule-modal-description']"
           )

    assert has_element?(view, "#rule-modal-title", "Add Rule")
    assert has_element?(view, "#rule-modal-description", "Configure schema-driven conditions")
    assert html =~ "Schema Field"
    assert html =~ "alert-schema-product"
    assert html =~ "Schema Version"
    assert html =~ "Create Rule"
    assert html =~ "Edit Alert Rules"
    assert html =~ "Active Alerts"
  end

  test "creates a rule successfully from modal", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    form_params = %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "High temperature",
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "75"
      }
    }

    render_submit(element(view, "#alert-rule-form"), form_params)

    assert_patch(view, ~p"/alerts?tab=rules")
    assert render(view) =~ "Rule created successfully"

    rules = Domain.list_rules!()

    assert Enum.any?(
             rules,
             &(&1.name == "High temperature" and &1.product_name == "alert-schema-product" and
                 &1.condition_field == "temp")
           )
  end

  test "duplicate rule names are rejected case-insensitively with preserved values", %{conn: conn} do
    {:ok, _existing_rule} =
      Domain.create_rule(%{
        name: "High Temperature",
        product_name: "alert-schema-product",
        condition_field: "temp",
        operator: ">",
        threshold_value: "75"
      })

    {:ok, view, _html} = live(conn, alert_new_path())

    duplicate_params = %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "high temperature",
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "75"
      }
    }

    render_change(element(view, "#alert-rule-form"), duplicate_params)

    assert has_element?(view, "#alert-rule-name-error", "Alert rule name is already used.")
    assert has_element?(view, "#alert-rule-name[aria-describedby='alert-rule-name-error'][aria-invalid='true']")
    assert has_element?(view, "#alert-rule-save[disabled]")

    render_submit(element(view, "#alert-rule-form"), duplicate_params)

    assert has_element?(view, "#rule-modal")
    assert has_element?(view, "#alert-rule-name[value='high temperature']")
    assert render(view) =~ "Alert rule name is already used."
    assert length(Enum.filter(Domain.list_rules!(), &(String.downcase(&1.name) == "high temperature"))) == 1
  end

  test "duplicate modal submissions persist one rule and emit one success measurement", %{conn: conn} do
    handler_id = "alert-rule-success-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(
        handler_id,
        [:nixstasis, :builder, :first_attempt_success],
        fn _event, measurements, metadata, test_pid ->
          if metadata[:builder] == "alert" do
            send(test_pid, {:alert_rule_success, measurements})
          end
        end,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    {:ok, view, _html} = live(conn, alert_new_path())
    form = element(view, "#alert-rule-form")

    params = %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Duplicate submission rule",
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "75"
      }
    }

    render_submit(form, params)
    render_submit(view, "save_rule", params)

    assert [rule] = Enum.filter(Domain.list_rules!(), &(&1.name == "Duplicate submission rule"))
    assert rule.threshold_value == "75"
    assert_receive {:alert_rule_success, %{count: 1}}
    refute_receive {:alert_rule_success, %{count: 1}}, 100
  end

  test "rule success flash clears after the short timeout", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())
    pid = view.pid
    :erlang.trace(pid, true, [:receive])

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Short flash rule",
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "75"
      }
    })

    assert render(view) =~ "Rule created successfully"

    assert_receive {:trace, ^pid, :receive, {:clear_flash, :info, 1}}, @success_flash_timeout_ms + 500

    :sys.get_state(pid)
    refute render(view) =~ "Rule created successfully"
  end

  test "older success flash timer does not clear a newer success message", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())
    pid = view.pid
    :erlang.trace(pid, true, [:receive])

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "First rule",
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "75"
      }
    })

    assert_patch(view, ~p"/alerts?tab=rules")

    view
    |> element("a[href='/alerts/new?tab=rules']", "Add Rule")
    |> render_click()

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Second rule",
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "80"
      }
    })

    assert render(view) =~ "Rule created successfully"
    assert_receive {:trace, ^pid, :receive, {:clear_flash, :info, 1}}, @success_flash_timeout_ms + 500

    :sys.get_state(pid)
    assert render(view) =~ "Rule created successfully"
  end

  test "edits an existing rule", %{conn: conn} do
    {:ok, rule} =
      Domain.create_rule(%{
        name: "Existing rule",
        product_name: "alert-schema-product",
        condition_field: "temp",
        operator: ">",
        threshold_value: "80"
      })

    {:ok, view, html} = live(conn, alert_edit_path(rule.id))
    assert html =~ "Edit Rule"
    assert has_element?(view, "#alert-rule-save", "Save Changes")
    assert has_element?(view, "#alert-rule-form[data-initial-focus-id='alert-schema-id']")

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Attempted rename",
        "condition_field" => "temp",
        "operator" => "<=",
        "threshold_value" => "42"
      }
    })

    assert_patch(view, ~p"/alerts?tab=rules")
    assert render(view) =~ "Rule updated successfully"

    updated_rule = Domain.get_rule!(rule.id)
    assert updated_rule.threshold_value == "42"
    assert to_string(updated_rule.operator) == "<="
    assert updated_rule.name == "Existing rule"
  end

  test "edit mode with unchanged numeric threshold does not show threshold type error", %{
    conn: conn
  } do
    {:ok, rule} =
      Domain.create_rule(%{
        product_name: "alert-schema-product",
        condition_field: "temp",
        operator: ">",
        threshold_value: "50"
      })

    {:ok, view, _html} = live(conn, alert_edit_path(rule.id))

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "50"
      }
    })

    refute render(view) =~ "Threshold value is invalid for the selected field type."

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "50"
      }
    })

    refute render(view) =~ "Threshold value is invalid for the selected field type."
    assert has_element?(view, "#rule-modal")
  end

  test "edit supports valid numeric threshold change from 50 to 51", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:39",
        "product_name" => "weather-station",
        "schema" => %{
          "product" => "weather-station",
          "version" => "v1",
          "properties" => %{
            "rainfall" => %{"type" => "number"},
            "status" => %{"type" => "string"},
            "wind_speed" => %{"type" => "number"}
          }
        }
      })

    {:ok, rule} =
      Domain.create_rule(%{
        product_name: "weather-station",
        condition_field: "rainfall",
        operator: ">=",
        threshold_value: "50"
      })

    {:ok, view, _html} = live(conn, alert_edit_path(rule.id))

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "weather-station",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "rainfall",
        "operator" => ">=",
        "threshold_value" => "51"
      }
    })

    assert_patch(view, ~p"/alerts?tab=rules")
    refute render(view) =~ "Threshold value is invalid for the selected field type."

    updated_rule = Domain.get_rule!(rule.id)
    assert updated_rule.threshold_value == "51"
  end

  test "edit flow keeps only rule name immutable and allows schema settings changes", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:41",
        "product_name" => "weather-editable",
        "schema" => %{
          "product" => "weather-editable",
          "version" => "v1",
          "properties" => %{
            "rainfall" => %{"type" => "number"}
          }
        }
      })

    {:ok, rule} =
      Domain.create_rule(%{
        name: "Original immutable name",
        product_name: "alert-schema-product",
        condition_field: "status",
        operator: "=",
        threshold_value: "ok"
      })

    {:ok, view, _html} = live(conn, alert_edit_path(rule.id))

    assert has_element?(view, "#alert-rule-name[disabled]")
    refute has_element?(view, "#alert-schema-id[disabled]")
    refute has_element?(view, "#alert-schema-version[disabled]")
    refute has_element?(view, "#alert-condition-field[disabled]")

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "weather-editable",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Renamed by submit",
        "condition_field" => "rainfall",
        "operator" => ">=",
        "threshold_value" => "12"
      }
    })

    assert_patch(view, ~p"/alerts?tab=rules")
    updated_rule = Domain.get_rule!(rule.id)
    assert updated_rule.name == "Original immutable name"
    assert updated_rule.product_name == "weather-editable"
    assert updated_rule.condition_field == "rainfall"
    assert to_string(updated_rule.operator) == ">="
    assert updated_rule.threshold_value == "12"
  end

  test "invalid schema field is blocked with actionable error", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "invalid.path",
        "operator" => ">",
        "threshold_value" => "75"
      }
    })

    html = render(view)
    assert html =~ "Please select a valid schema field before saving."
  end

  test "name-only modal edits ask for discard confirmation on cancel", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{"name" => "Draft rule"}
    })

    render_keydown(view, "keydown", %{"key" => "Escape"})

    assert has_element?(view, "#discard-rule-modal")
  end

  test "dirty modal asks for discard confirmation on cancel", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "50"
      }
    })

    render_keydown(view, "keydown", %{"key" => "Escape"})

    assert has_element?(view, "#discard-rule-modal[data-focus-target='discard-rule-keep-editing']")
    assert has_element?(view, "#discard-rule-modal")
    assert has_element?(view, "#rule-modal")
    assert has_element?(view, "#discard-rule-keep-editing")

    assert has_element?(
             view,
             "#discard-rule-modal [role='dialog'][aria-labelledby='discard-rule-modal-title'][aria-describedby='discard-rule-modal-description']"
           )

    assert has_element?(view, "#discard-rule-modal-title", "Discard Changes?")
    assert has_element?(view, "#discard-rule-modal-description", "unsaved edits")
    assert render(view) =~ "Discard Changes?"

    render_click(element(view, "#discard-rule-modal button", "Keep Editing"))
    assert has_element?(view, "#rule-modal")
  end

  test "modal includes keyboard hook and focus starts on first control", %{conn: conn} do
    {:ok, view, html} = live(conn, alert_new_path())

    assert html =~ "phx-hook=\"AlertRuleBuilderKeyboard\""
    assert has_element?(view, "#alert-rule-form[data-initial-focus-id='alert-rule-name']")
    assert has_element?(view, "#alert-schema-id")
    assert has_element?(view, "#alert-rule-save")
  end

  test "rule can be deleted from rules table", %{conn: conn} do
    {:ok, rule} =
      Domain.create_rule(%{
        product_name: "alert-schema-product",
        condition_field: "status",
        operator: "=",
        threshold_value: "ok"
      })

    {:ok, view, _html} = live(conn, ~p"/alerts?tab=rules")

    render_click(element(view, "button[phx-click='confirm_delete_rule'][phx-value-id='#{rule.id}']"))

    assert has_element?(view, "#delete-rule-modal")

    render_click(element(view, "#delete-rule-modal button", "Delete"))

    refute Enum.any?(Domain.list_rules!(), &(&1.id == rule.id))
    assert render(view) =~ "Rule deleted"
  end

  test "schema product/version selections persist across schema selector changes", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "alert_rule" => %{
        "condition_field" => "temp",
        "operator" => ">",
        "threshold_value" => "10"
      }
    })

    assert has_element?(view, "#alert-schema-id option[value='alert-schema-product'][selected]")
    assert has_element?(view, "#alert-schema-version option[value='v1'][selected]")
    assert has_element?(view, "#alert-condition-field option[value='temp']")
  end

  test "explicit schema version selection drives alert schema options", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v2",
      "alert_rule" => %{
        "condition_field" => "pressure",
        "operator" => ">",
        "threshold_value" => "10"
      }
    })

    assert has_element?(view, "#alert-schema-version option[value='v2'][selected]")
    assert has_element?(view, "#alert-condition-field option[value='pressure']")
    refute has_element?(view, "#alert-condition-field option[value='temp']")
  end

  test "schema with no fields blocks save and shows guidance", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:32",
        "product_name" => "empty-schema-product",
        "schema" => %{"product" => "empty-schema-product", "version" => "v1", "properties" => %{}}
      })

    {:ok, view, _html} = live(conn, alert_new_path())

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "empty-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "",
        "operator" => "=",
        "threshold_value" => "x"
      }
    })

    assert render(view) =~ "No schema fields are available for this schema/version."

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "empty-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "",
        "operator" => "=",
        "threshold_value" => "x"
      }
    })

    assert render(view) =~ "This schema has no available fields for rules."
  end

  test "operator and value validation transitions from invalid to valid", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Invalid status operator",
        "condition_field" => "status",
        "operator" => ">",
        "threshold_value" => "ok"
      }
    })

    assert render(view) =~ "Operator is not valid for the selected field type."

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Status is ok",
        "condition_field" => "status",
        "operator" => "=",
        "threshold_value" => "ok"
      }
    })

    assert_patch(view, ~p"/alerts?tab=rules")
    assert render(view) =~ "Rule created successfully"
  end

  test "modal labels and error announcements are accessible", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    assert has_element?(view, "label[for='alert-schema-id']")
    assert has_element?(view, "#rule-modal [role='dialog']")

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "condition_field" => "status",
        "operator" => ">",
        "threshold_value" => "ok"
      }
    })

    assert has_element?(view, "#rule-modal [role='alert']")
    assert has_element?(view, "#alert-rule-validation-error[role='alert']")
  end

  test "rules table filtering and sorting controls are visible", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/alerts?tab=rules")

    assert html =~ "Filter rules"
    assert html =~ "Clear"
    assert html =~ "Rule"
    assert html =~ "Condition"
    assert html =~ "Operator"
  end

  test "deprecated rules hide edit action and show warning label with reason tooltip", %{
    conn: conn
  } do
    {:ok, rule} =
      Domain.create_rule(%{
        product_name: "alert-schema-product",
        condition_field: "legacy_field_that_no_longer_exists",
        operator: "=",
        threshold_value: "ok"
      })

    {:ok, view, _html} = live(conn, ~p"/alerts?tab=rules")

    assert render(view) =~ "Deprecated"

    assert has_element?(view, "span.badge.badge-warning.badge-xs", "Deprecated")
    refute has_element?(view, "button[aria-label='Edit rule #{rule.id}']")
  end

  test "clicking edit icon opens edit rule modal", %{conn: conn} do
    {:ok, rule} =
      Domain.create_rule(%{
        product_name: "alert-schema-product",
        condition_field: "temp",
        operator: ">",
        threshold_value: "90"
      })

    {:ok, view, _html} = live(conn, ~p"/alerts?tab=rules")

    render_click(element(view, "button[phx-click='edit_rule'][phx-value-id='#{rule.id}']"))

    assert_patch(view, ~p"/alerts/#{rule.id}/edit?tab=rules")
    assert has_element?(view, "#rule-modal")
    assert render(view) =~ "Edit Rule"
  end

  test "string fields show string-specific operators", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "alert_rule" => %{
        "condition_field" => "status",
        "operator" => "is",
        "threshold_value" => "ok"
      }
    })

    assert has_element?(view, "#alert-operator option[value='contains']")
    assert has_element?(view, "#alert-operator option[value=\"doesn't contain\"]")
    assert has_element?(view, "#alert-operator option[value='is']")
    assert has_element?(view, "#alert-operator option[value='is not']")
  end

  test "string field accepts alphanumeric threshold values", %{conn: conn} do
    {:ok, view, _html} = live(conn, alert_new_path())

    render_submit(element(view, "#alert-rule-form"), %{
      "schema_id" => "alert-schema-product",
      "schema_version" => "v1",
      "alert_rule" => %{
        "name" => "Status alphanumeric",
        "condition_field" => "status",
        "operator" => "is",
        "threshold_value" => "ok42"
      }
    })

    assert_patch(view, ~p"/alerts?tab=rules")

    assert Enum.any?(Domain.list_rules!(), fn rule ->
             rule.product_name == "alert-schema-product" and
               rule.condition_field == "status" and
               rule.threshold_value == "ok42"
           end)
  end

  test "edit flow accepts mixed form namespaces from browser payload", %{conn: conn} do
    {:ok, _device} =
      Devices.register_device(%{
        "mac_address" => "AA:BB:CC:DD:EE:40",
        "product_name" => "weather-station",
        "schema" => %{
          "product" => "weather-station",
          "version" => "v1",
          "properties" => %{
            "rainfall" => %{"type" => "number"}
          }
        }
      })

    {:ok, rule} =
      Domain.create_rule(%{
        product_name: "weather-station",
        condition_field: "rainfall",
        operator: ">=",
        threshold_value: "50"
      })

    {:ok, view, _html} = live(conn, alert_edit_path(rule.id))

    render_change(element(view, "#alert-rule-form"), %{
      "schema_id" => "weather-station",
      "form" => %{"operator" => ">=", "threshold_value" => "51"},
      "alert_rule" => %{"condition_field" => "rainfall"}
    })

    refute render(view) =~ "Threshold value is invalid for the selected field type."
  end
end
