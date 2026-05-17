defmodule Nixstasis.ReportingTest do
  use Nixstasis.DataCase, async: true

  alias Nixstasis.Repo
  alias Nixstasis.Reporting

  test "view preferences are durable and do not rely on ETS" do
    scope = Reporting.preference_scope(%{"kind" => "report_live", "owner" => "durable"})

    assert :ok = Reporting.save_view_preferences(scope, "reports:index", %{"sort_by" => "name", "sort_dir" => "desc"})

    if :ets.whereis(:report_view_preferences) != :undefined do
      :ets.delete(:report_view_preferences)
    end

    assert %{"sort_by" => "name", "sort_dir" => "desc"} =
             Reporting.load_view_preferences(scope, "reports:index")
  end

  test "reporting preference access does not expose runtime DDL helper" do
    refute function_exported?(Reporting, :ensure_preference_store!, 0)
  end

  test "view preference writes are scoped to explicit scope keys" do
    owner_scope = Reporting.preference_scope(%{"kind" => "report_live", "owner" => "owner-a", "csrf" => "ignored-a"})

    unrelated_scope =
      Reporting.preference_scope(%{"kind" => "report_live", "owner" => "owner-b", "csrf" => "ignored-a"})

    assert owner_scope != unrelated_scope

    assert :ok = Reporting.save_view_preferences(owner_scope, "reports:index", %{"sort_dir" => "desc"})
    assert :ok = Reporting.save_view_preferences(unrelated_scope, "reports:index", %{"sort_dir" => "asc"})

    assert %{"sort_dir" => "desc"} = Reporting.load_view_preferences(owner_scope, "reports:index")
    assert %{"sort_dir" => "asc"} = Reporting.load_view_preferences(unrelated_scope, "reports:index")

    assert owner_scope ==
             Reporting.preference_scope(%{"kind" => "report_live", "owner" => "owner-a", "csrf" => "different"})
  end

  test "ordinary sessions without explicit durable scope do not persist preferences" do
    assert is_nil(Reporting.preference_scope(%{"_csrf_token" => "csrf-a"}))
    assert is_nil(Reporting.preference_scope(%{"anything_else" => "not-a-scope"}))
    assert is_nil(Reporting.preference_scope(%{"report_permissions" => %{"can_view" => true, "can_manage" => true}}))

    assert :ok = Reporting.save_view_preferences(nil, "reports:index", %{"sort_dir" => "desc"})
    assert %{} == Reporting.load_view_preferences(nil, "reports:index")
  end

  test "dedicated durable scope inputs are accepted without csrf-derived scope" do
    owner_scope = Reporting.preference_scope(%{"report_preferences" => %{"owner" => "operator-a"}})
    operator_scope = Reporting.preference_scope(%{"operator_id" => "operator-b", "_csrf_token" => "ignored"})
    named_scope = Reporting.preference_scope(%{"report_preference_scope" => "ops-desk"})

    assert owner_scope == "kind=report_live;owner=operator-a"
    assert operator_scope == "kind=report_live;operator=operator-b"
    assert named_scope == "kind=report_live;scope=ops-desk"

    assert :ok = Reporting.save_view_preferences(operator_scope, "reports:index", %{"sort_dir" => "desc"})
    assert %{"sort_dir" => "desc"} = Reporting.load_view_preferences(operator_scope, "reports:index")
  end

  test "malformed stored preferences fail safe to defaults" do
    scope = "kind=report_live;owner=malformed"
    now = DateTime.utc_now()

    Repo.insert_all(
      "report_view_preferences",
      [
        %{
          scope: scope,
          view_key: "reports:index",
          preferences: "invalid",
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: {:replace, [:preferences, :updated_at]},
      conflict_target: [:scope, :view_key]
    )

    assert %{} == Reporting.load_view_preferences(scope, "reports:index")
  end

  test "custom report index filters and sorts in the database-backed path" do
    {:ok, _} =
      Reporting.create_custom_report(%{
        "name" => "Zulu DB Report",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "temp"}], "filters" => []}
      })

    {:ok, _} =
      Reporting.create_custom_report(%{
        "name" => "Alpha DB Report",
        "config" => %{"source" => "telemetry", "fields" => [%{"path" => "humidity"}], "filters" => []}
      })

    rows =
      Reporting.list_custom_reports_with_view(%{
        "sort_by" => "name",
        "sort_dir" => "asc",
        "field_queries" => ["humidity"]
      })

    assert ["Alpha DB Report"] == Enum.map(rows, & &1["name"])
  end
end
