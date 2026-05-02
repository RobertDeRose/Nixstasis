defmodule NixstasisWeb.LiveDashboard.E2ELogPresenterTest do
  use ExUnit.Case, async: true

  alias NixstasisWeb.LiveDashboard.E2ELogPresenter

  test "journey start/complete-only logs are suppressed" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.000Z",
          "level" => "journey",
          "event" => "started",
          "status" => "running",
          "journey_id" => "runtime_linux_telemetry",
          "run" => %{
            "run_id" => "run-1",
            "suite_id" => "runtime"
          }
        },
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.500Z",
          "level" => "journey",
          "event" => "completed",
          "status" => "passed",
          "journey_id" => "runtime_linux_telemetry",
          "duration_ms" => 500,
          "steps_run" => 0,
          "steps_passed" => 0,
          "steps_failed" => 0
        }
      ])

    entries = E2ELogPresenter.parse_entries(log)

    assert entries == []
  end

  test "single-step entries do not include summary row or step numbering" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.100Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => "runtime_register_device",
          "action" => "runtime_register_device",
          "expect" => "runtime_device_registered",
          "status" => "passed",
          "duration_ms" => 70
        }
      ])

    [step_entry] = E2ELogPresenter.parse_entries(log)

    assert step_entry.kind == "step"
    assert step_entry.step_header.action == "runtime_register_device"
    assert step_entry.step_header.expected == "runtime_device_registered"
    assert step_entry.step_header.status == "passed"
    assert step_entry.duration_ms == 70
    assert step_entry.icon_label == "STEP"
  end

  test "summary uses timeline timestamps, step counts, and multi-step numbering" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.000Z",
          "level" => "journey",
          "event" => "started",
          "status" => "running",
          "journey_id" => "runtime_linux_telemetry"
        },
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.250Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => "runtime_register_device",
          "action" => "runtime_register_device",
          "expect" => "runtime_device_registered",
          "status" => "passed",
          "duration_ms" => 70
        },
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.900Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => "runtime_verify_alert",
          "action" => "runtime_verify_alert",
          "expect" => "alert_triggered",
          "status" => "failed",
          "duration_ms" => 120,
          "error_code" => "ASSERTION_FAILED"
        }
      ])

    entries = E2ELogPresenter.parse_entries(log)
    [first_step, second_step, summary] = entries

    assert first_step.icon_label == "STEP 01"
    assert second_step.icon_label == "STEP 02"

    assert summary.kind == "summary"
    assert summary.status == "failed"
    assert summary.summary.total_duration_ms == 900
    assert summary.summary.total_count == 2
    assert summary.summary.passed_count == 1
    assert summary.summary.failed_count == 1
  end

  test "step panels expose response/action panels and move response fields out of metadata" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.100Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => "runtime_register_device",
          "action" => "runtime_register_device",
          "expect" => "runtime_device_registered",
          "status" => "passed",
          "duration_ms" => 70,
          "http_status" => 201,
          "response_type" => "json_response",
          "bytes" => 254,
          "action_data" => %{
            "body_json" => %{"data" => %{"id" => "abc"}},
            "device_id" => "abc"
          }
        }
      ])

    [step_entry] = E2ELogPresenter.parse_entries(log)

    assert length(step_entry.data_panels) == 2
    assert Enum.at(step_entry.data_panels, 0).title == "JSON Response"
    assert Enum.at(step_entry.data_panels, 1).title == "Action Data"
    assert Enum.at(step_entry.data_panels, 0).http_status == 201
    assert Enum.at(step_entry.data_panels, 0).bytes == 254
    assert step_entry.metadata == %{}
    refute Map.has_key?(step_entry.metadata, "action")
    refute Map.has_key?(step_entry.metadata, "expect")
  end

  test "step without response body renders with no extra metadata" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.200Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => "runtime_cleanup",
          "action" => "runtime_cleanup",
          "expect" => "runtime_resources_cleaned",
          "status" => "passed",
          "duration_ms" => 45
        }
      ])

    [step_entry] = E2ELogPresenter.parse_entries(log)

    assert step_entry.data_panels == []
    assert step_entry.metadata == %{}
  end

  test "nil action/step_id fallback does not render literal nil" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.200Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => nil,
          "action" => nil,
          "expect" => "runtime_resources_cleaned",
          "status" => "passed",
          "duration_ms" => 45
        }
      ])

    [step_entry] = E2ELogPresenter.parse_entries(log)
    assert step_entry.step_header.action == "—"
  end

  test "step header prefers step_id when provided and different from action" do
    log =
      encode_lines([
        %{
          "schema" => "e2e_log.v1",
          "timestamp" => "2026-02-13T20:13:00.200Z",
          "level" => "step",
          "journey_id" => "runtime_linux_telemetry",
          "step_id" => "register_phase",
          "action" => "runtime_register_device",
          "expect" => "runtime_device_registered",
          "status" => "passed",
          "duration_ms" => 45
        }
      ])

    [step_entry] = E2ELogPresenter.parse_entries(log)
    assert step_entry.step_header.action == "register_phase"
  end

  defp encode_lines(entries) do
    Enum.map_join(entries, "\n", &Jason.encode!/1) <> "\n"
  end
end
