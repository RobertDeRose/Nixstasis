#!/usr/bin/env bash
set -euo pipefail

RESULTS_DIR="${1:-e2e-results}"
OUTPUT_FILE="${2:-docs/src/reference/e2e-results.md}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

python3 - "$RESULTS_DIR" "$OUTPUT_FILE" <<'PY'
import json
import pathlib
import sys

results_dir = pathlib.Path(sys.argv[1])
output_file = pathlib.Path(sys.argv[2])
manifest_path = results_dir / "runs.json"

lines = [
    "# E2E Results",
    "",
    "Published E2E run reports are stored separately from the mdBook site and linked here during the docs deployment.",
    "",
]

if not manifest_path.exists():
    lines.extend([
        "No E2E results have been published yet.",
        "",
    ])
else:
    manifest = json.loads(manifest_path.read_text())
    runs = manifest.get("runs") or []
    if not runs:
        lines.extend([
            "No E2E results have been published yet.",
            "",
        ])
    else:
        lines.extend([
            "| Ref | Commit | Timestamp | Report |",
            "| --- | --- | --- | --- |",
        ])

        for run in runs:
            ref_name = run.get("ref_name") or "unknown"
            short_sha = run.get("short_commit_sha") or "unknown"
            timestamp = run.get("timestamp") or "unknown"
            run_path = (run.get("run_path") or "").strip("/")
            href = f"../e2e-results/{run_path}/index.html" if run_path else "../e2e-results/index.html"
            lines.append(f"| `{ref_name}` | `{short_sha}` | {timestamp} | [Open report]({href}) |")

        lines.append("")
        lines.extend([
            "[Open the full E2E report index](../e2e-results/index.html).",
            "",
        ])

output_file.write_text("\n".join(lines))
PY
