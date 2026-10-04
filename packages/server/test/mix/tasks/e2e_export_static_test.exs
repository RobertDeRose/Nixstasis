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

  test "renders untrusted static export values only through text-safe DOM sinks", %{
    reports_dir: reports_dir,
    logs_dir: logs_dir,
    pages_dir: pages_dir
  } do
    ref_name = ~s(feature-<img src=x onerror="globalThis.__xss_ref=1">)
    title = ~s(E2E </h1><script>globalThis.__xss_title=1</script>)
    run_id = ~s(run-<img src=x onerror="globalThis.__xss_run=1">)
    run_status = ~s(<script>globalThis.__xss_status=1</script>)
    journey_id = ~s(journey-<svg onload="globalThis.__xss_journey=1">)
    journey_status = ~s(<b onclick="globalThis.__xss_journey_status=1">failed</b>)
    duration = ~s(<img src=x onerror="globalThis.__xss_duration=1">)
    error = ~s(<img src=x onerror="globalThis.__xss_error=1">)

    report = %{
      "RunID" => run_id,
      "Status" => run_status,
      "Journeys" => [
        %{
          "JourneyID" => journey_id,
          "Status" => journey_status,
          "Error" => error,
          "DurationMs" => duration
        }
      ]
    }

    File.write!(Path.join(reports_dir, "malicious.json"), Jason.encode!(report))

    run_task([
      "--reports-dir",
      reports_dir,
      "--logs-dir",
      logs_dir,
      "--pages-dir",
      pages_dir,
      "--title",
      title,
      "--ref-name",
      ref_name,
      "--ref-type",
      "branch",
      "--full-sha",
      "abcdef1234567890",
      "--timestamp",
      "2026-02-14T10:00:00Z"
    ])

    manifest = pages_dir |> Path.join("runs.json") |> File.read!() |> Jason.decode!()
    [entry] = manifest["runs"]
    assert entry["ref_name"] == ref_name

    run_dir = Path.join(pages_dir, String.trim_trailing(entry["run_path"], "/"))
    run_data = run_dir |> Path.join("run.json") |> File.read!() |> Jason.decode!()
    [exported_report] = run_data["reports"]
    [exported_journey] = exported_report["Journeys"]

    assert run_data["ref_name"] == ref_name
    assert exported_report["RunID"] == run_id
    assert exported_report["Status"] == run_status
    assert exported_journey["JourneyID"] == journey_id
    assert exported_journey["Status"] == journey_status
    assert exported_journey["DurationMs"] == duration
    assert exported_journey["Error"] == error

    index_html = File.read!(Path.join(pages_dir, "index.html"))
    run_html = File.read!(Path.join(run_dir, "index.html"))
    escaped_title = title |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    assert index_html =~ "<title>#{escaped_title}</title>"
    assert index_html =~ "<h1>#{escaped_title}</h1>"
    refute index_html =~ title

    for html <- [index_html, run_html], sink <- ["innerHTML", "outerHTML", "insertAdjacentHTML", "document.write"] do
      refute html =~ sink
    end

    assert index_html =~ "heading.textContent = name"
    assert index_html =~ ~s'link.textContent = String(run.short_commit_sha || "")'
    assert index_html =~ ~s'appendTextCell(row, run.full_commit_sha)'

    assert run_html =~
             ~s'reportHeading.textContent = `Run ${String(report.RunID || "unknown")} (${String(report.Status || "unknown")})`'

    assert run_html =~ ~s'appendTextCell(row, "td", journey.JourneyID || "")'
    assert run_html =~ ~s'appendTextCell(row, "td", journey.Status || "")'
    assert run_html =~ ~s'appendTextCell(row, "td", journey.DurationMs ?? "")'
    assert run_html =~ ~s'appendTextCell(row, "td", journey.Error || "")'

    for payload <- [ref_name, run_id, run_status, journey_id, journey_status, duration, error] do
      refute index_html =~ payload
      refute run_html =~ payload
    end
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
