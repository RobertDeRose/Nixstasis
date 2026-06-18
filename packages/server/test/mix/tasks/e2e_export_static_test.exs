defmodule Mix.Tasks.E2e.ExportStaticTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.E2e.ExportStatic

  @task "e2e.export_static"

  setup do
    tmp = Path.join(System.tmp_dir!(), "e2e-export-static-#{System.unique_integer([:positive, :monotonic])}")
    reports_dir = Path.join(tmp, "reports")
    logs_dir = Path.join(tmp, "logs")
    pages_dir = Path.join(tmp, "pages")
    File.mkdir_p!(reports_dir)
    File.mkdir_p!(logs_dir)
    File.mkdir_p!(pages_dir)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{tmp: tmp, reports_dir: reports_dir, logs_dir: logs_dir, pages_dir: pages_dir}
  end

  test "creates run directory and manifest entry", %{reports_dir: reports_dir, logs_dir: logs_dir, pages_dir: pages_dir} do
    write_report_fixture(reports_dir, logs_dir, "run-1", "auth")

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "main",
      "--ref-type",
      "branch",
      "--full-sha",
      "abcdef1234567890",
      "--timestamp",
      "2026-02-14T10:00:00Z",
      "--max-runs",
      "2"
    ])

    assert File.exists?(Path.join(pages_dir, "runs/main/abcdef1/index.html"))
    assert File.exists?(Path.join(pages_dir, "runs/main/abcdef1/run.json"))
    assert File.exists?(Path.join(pages_dir, "runs.json"))

    manifest = pages_dir |> Path.join("runs.json") |> File.read!() |> Jason.decode!()
    [entry] = manifest["runs"]
    assert entry["ref_name"] == "main"
    assert entry["ref_type"] == "branch"
    assert entry["short_commit_sha"] == "abcdef1"
    assert entry["run_path"] == "runs/main/abcdef1/"
    assert entry["is_release"] == false
  end

  test "prunes oldest non-release runs by max limit", %{
    reports_dir: reports_dir,
    logs_dir: logs_dir,
    pages_dir: pages_dir
  } do
    write_report_fixture(reports_dir, logs_dir, "run-a", "auth")

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "feature/a",
      "--ref-type",
      "branch",
      "--full-sha",
      "aaaaaaaaaaaaaaa1",
      "--timestamp",
      "2026-02-14T10:00:00Z",
      "--max-runs",
      "2"
    ])

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "feature/b",
      "--ref-type",
      "branch",
      "--full-sha",
      "bbbbbbbbbbbbbbb2",
      "--timestamp",
      "2026-02-14T11:00:00Z",
      "--max-runs",
      "2"
    ])

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "feature/c",
      "--ref-type",
      "branch",
      "--full-sha",
      "ccccccccccccccc3",
      "--timestamp",
      "2026-02-14T12:00:00Z",
      "--max-runs",
      "2"
    ])

    manifest = pages_dir |> Path.join("runs.json") |> File.read!() |> Jason.decode!()
    assert length(manifest["runs"]) == 2
    refute Enum.any?(manifest["runs"], &(&1["full_commit_sha"] == "aaaaaaaaaaaaaaa1"))
    refute File.exists?(Path.join(pages_dir, "runs/feature/a/aaaaaaa"))
  end

  test "keeps semver tag runs even when non-release runs are pruned", %{
    reports_dir: reports_dir,
    logs_dir: logs_dir,
    pages_dir: pages_dir
  } do
    write_report_fixture(reports_dir, logs_dir, "run-r", "auth")

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "v1.2.3",
      "--ref-type",
      "tag",
      "--full-sha",
      "ddddddddddddddd4",
      "--timestamp",
      "2026-02-14T10:00:00Z",
      "--max-runs",
      "1"
    ])

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "feature/d",
      "--ref-type",
      "branch",
      "--full-sha",
      "eeeeeeeeeeeeeee5",
      "--timestamp",
      "2026-02-14T11:00:00Z",
      "--max-runs",
      "1"
    ])

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--ref-name",
      "feature/e",
      "--ref-type",
      "branch",
      "--full-sha",
      "fffffffffffffff6",
      "--timestamp",
      "2026-02-14T12:00:00Z",
      "--max-runs",
      "1"
    ])

    manifest = pages_dir |> Path.join("runs.json") |> File.read!() |> Jason.decode!()
    assert Enum.any?(manifest["runs"], &(&1["ref_name"] == "v1.2.3" and &1["is_release"] == true))
    assert Enum.any?(manifest["runs"], &(&1["full_commit_sha"] == "fffffffffffffff6"))
    refute Enum.any?(manifest["runs"], &(&1["full_commit_sha"] == "eeeeeeeeeeeeeee5"))
  end

  defp run_task(args) do
    Mix.Task.reenable(@task)
    ExportStatic.run(args)
  end

  defp write_report_fixture(reports_dir, logs_dir, run_id, journey_id) do
    payload = %{
      "RunID" => run_id,
      "Status" => "passed",
      "Journeys" => [
        %{
          "JourneyID" => journey_id,
          "Status" => "passed",
          "Error" => "",
          "DurationMs" => 42
        }
      ]
    }

    File.write!(Path.join(reports_dir, "#{run_id}.json"), Jason.encode!(payload))

    log_dir = Path.join(logs_dir, run_id)
    File.mkdir_p!(log_dir)

    log_line =
      Jason.encode!(%{
        "schema" => "e2e_log.v1",
        "timestamp" => "2026-02-14T10:00:00Z",
        "level" => "step",
        "status" => "passed",
        "action" => "register_device",
        "expect" => "uuid_returned",
        "duration_ms" => 12
      })

    File.write!(Path.join(log_dir, "001-#{journey_id}.log"), log_line <> "\n")
  end
end
