#!/usr/bin/env python3
"""Export E2E run summaries/logs to a static HTML report."""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export E2E static report")
    parser.add_argument("--reports-dir", required=True, help="Directory with run summary JSON files")
    parser.add_argument("--logs-dir", required=True, help="Directory with per-run log directories")
    parser.add_argument("--output-dir", required=True, help="Directory to write static HTML output")
    parser.add_argument("--title", default="Nixstasis E2E Report", help="Report title")
    return parser.parse_args()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_reports(reports_dir: Path) -> list[dict]:
    reports: list[dict] = []
    for file in sorted(reports_dir.glob("*.json")):
        payload = read_json(file)
        payload["_report_file"] = file.name
        reports.append(payload)
    return reports


def status_class(status: str) -> str:
    status = (status or "").lower()
    if status == "passed":
        return "status-pass"
    if status == "failed":
        return "status-fail"
    return "status-neutral"


def render_report_rows(reports: list[dict]) -> str:
    rows = []
    for rep in reports:
        run_id = rep.get("RunID", "")
        status = rep.get("Status", "unknown")
        journeys = rep.get("Journeys", [])
        pass_count = sum(1 for j in journeys if j.get("Status") == "passed")
        fail_count = sum(1 for j in journeys if j.get("Status") == "failed")

        rows.append(
            "<tr>"
            f"<td><a href='runs/{html.escape(run_id)}/index.html'>{html.escape(run_id)}</a></td>"
            f"<td class='{status_class(status)}'>{html.escape(status)}</td>"
            f"<td>{len(journeys)}</td>"
            f"<td>{pass_count}</td>"
            f"<td>{fail_count}</td>"
            f"<td>{html.escape(rep.get('_report_file', ''))}</td>"
            "</tr>"
        )

    return "\n".join(rows)


def render_journey_table(journeys: list[dict]) -> str:
    rows = []
    for journey in journeys:
        rows.append(
            "<tr>"
            f"<td>{html.escape(str(journey.get('JourneyID', '')))}</td>"
            f"<td class='{status_class(str(journey.get('Status', '')))}'>{html.escape(str(journey.get('Status', '')))}</td>"
            f"<td>{html.escape(str(journey.get('DurationMs', '')))}</td>"
            f"<td>{html.escape(str(journey.get('Error', '')))}</td>"
            "</tr>"
        )
    return "\n".join(rows)


def render_log_blocks(log_files: list[Path]) -> str:
    if not log_files:
        return "<p>No log files found for this run.</p>"

    blocks = []
    for log_file in log_files:
        raw_content = log_file.read_text(encoding="utf-8", errors="replace")
        blocks.append(
            "<details>"
            f"<summary>{html.escape(log_file.name)}</summary>"
            f"<pre>{html.escape(raw_content)}</pre>"
            "</details>"
        )
    return "\n".join(blocks)


def render_run_page(output_root: Path, logs_dir: Path, report: dict) -> None:
    run_id = str(report.get("RunID", "")).strip()
    if not run_id:
        return

    run_dir = output_root / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    run_logs_dir = logs_dir / run_id
    log_files = sorted(run_logs_dir.glob("*.log")) if run_logs_dir.exists() else []

    html_page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>E2E Run {html.escape(run_id)}</title>
  <style>
    body {{ font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin: 2rem; background: #f5f7fb; color: #1f2937; }}
    h1, h2 {{ margin: 0 0 0.75rem 0; }}
    .card {{ background: #fff; border: 1px solid #d6deeb; border-radius: 8px; padding: 1rem; margin: 1rem 0; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{ border-bottom: 1px solid #e5e7eb; padding: 0.5rem; text-align: left; vertical-align: top; }}
    .status-pass {{ color: #166534; font-weight: 700; }}
    .status-fail {{ color: #991b1b; font-weight: 700; }}
    .status-neutral {{ color: #374151; font-weight: 600; }}
    pre {{ background: #0f172a; color: #e2e8f0; padding: 0.8rem; border-radius: 6px; overflow: auto; }}
    summary {{ cursor: pointer; font-weight: 600; margin: 0.4rem 0; }}
  </style>
</head>
<body>
  <p><a href="../../index.html">Back to index</a></p>
  <h1>E2E Run {html.escape(run_id)}</h1>
  <div class="card">
    <p><strong>Status:</strong> <span class="{status_class(str(report.get("Status", "")))}">{html.escape(str(report.get("Status", "unknown")))}</span></p>
    <p><strong>Summary File:</strong> {html.escape(str(report.get("_report_file", "")))}</p>
  </div>
  <div class="card">
    <h2>Journeys</h2>
    <table>
      <thead><tr><th>Journey</th><th>Status</th><th>Duration (ms)</th><th>Error</th></tr></thead>
      <tbody>{render_journey_table(report.get("Journeys", []))}</tbody>
    </table>
  </div>
  <div class="card">
    <h2>Logs</h2>
    {render_log_blocks(log_files)}
  </div>
</body>
</html>"""
    (run_dir / "index.html").write_text(html_page, encoding="utf-8")


def render_index(output_root: Path, reports: list[dict], title: str) -> None:
    generated_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")

    page = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin: 2rem; background: #f5f7fb; color: #1f2937; }}
    h1 {{ margin: 0 0 0.5rem 0; }}
    .muted {{ color: #6b7280; margin-bottom: 1rem; }}
    .card {{ background: #fff; border: 1px solid #d6deeb; border-radius: 8px; padding: 1rem; }}
    table {{ width: 100%; border-collapse: collapse; }}
    th, td {{ border-bottom: 1px solid #e5e7eb; padding: 0.5rem; text-align: left; }}
    .status-pass {{ color: #166534; font-weight: 700; }}
    .status-fail {{ color: #991b1b; font-weight: 700; }}
    .status-neutral {{ color: #374151; font-weight: 600; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  <p class="muted">Generated at {generated_at} (UTC)</p>
  <div class="card">
    <table>
      <thead><tr><th>Run ID</th><th>Status</th><th>Journeys</th><th>Passed</th><th>Failed</th><th>Source</th></tr></thead>
      <tbody>
        {render_report_rows(reports)}
      </tbody>
    </table>
  </div>
</body>
</html>"""

    (output_root / "index.html").write_text(page, encoding="utf-8")


def main() -> int:
    args = parse_args()
    reports_dir = Path(args.reports_dir)
    logs_dir = Path(args.logs_dir)
    output_dir = Path(args.output_dir)

    output_dir.mkdir(parents=True, exist_ok=True)
    reports = load_reports(reports_dir)
    for report in reports:
        render_run_page(output_dir, logs_dir, report)
    render_index(output_dir, reports, args.title)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
