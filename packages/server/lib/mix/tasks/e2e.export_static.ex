defmodule Mix.Tasks.E2e.ExportStatic do
  use Mix.Task

  alias NixstasisWeb.LiveDashboard.E2ELogPresenter

  @shortdoc "Exports static E2E pages and updates manifest retention"

  @shared_viewer_js_path Path.expand("../../../../shared/e2e_log_viewer/viewer.js", __DIR__)
  @shared_viewer_css_path Path.expand("../../../../shared/e2e_log_viewer/viewer.css", __DIR__)
  @external_resource @shared_viewer_js_path
  @external_resource @shared_viewer_css_path

  @manifest_version 1
  @default_max_runs 200
  @release_tag_regex ~r/^(?:v)?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/
  @help_text """
  usage: mix e2e.export_static [-h] --reports-dir REPORTS_DIR --logs-dir LOGS_DIR --pages-dir PAGES_DIR [--title TITLE] [--ref-name REF_NAME] [--ref-type REF_TYPE] [--full-sha FULL_SHA] [--timestamp TIMESTAMP] [--max-runs MAX_RUNS]

  Export manifest-led static E2E pages

  options:
    -h, --help                show this help message and exit
    --reports-dir REPORTS_DIR Directory with run summary JSON files
    --logs-dir LOGS_DIR       Directory with per-run log directories
    --pages-dir PAGES_DIR     Pages root directory (contains runs.json and runs/*)
    --title TITLE             Site title (default: Nixstasis E2E Reports)
    --ref-name REF_NAME       Git ref name (default: local)
    --ref-type REF_TYPE       branch or tag (default: branch)
    --full-sha FULL_SHA       Full commit sha (default: local)
    --timestamp TIMESTAMP     ISO8601 timestamp (default: now UTC)
    --max-runs MAX_RUNS       Max non-release runs to retain (default: 200)
  """

  @impl Mix.Task
  def run(args) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        aliases: [h: :help],
        strict: [
          help: :boolean,
          reports_dir: :string,
          logs_dir: :string,
          pages_dir: :string,
          title: :string,
          ref_name: :string,
          ref_type: :string,
          full_sha: :string,
          timestamp: :string,
          max_runs: :string
        ]
      )

    cond do
      Keyword.get(opts, :help, false) ->
        Mix.shell().info(@help_text)

      invalid != [] ->
        Mix.raise("invalid options: #{inspect(invalid)}")

      true ->
        do_run(opts)
    end
  end

  defp do_run(opts) do
    reports_dir = required_opt(opts, :reports_dir)
    logs_dir = required_opt(opts, :logs_dir)
    pages_dir = required_opt(opts, :pages_dir)
    title = Keyword.get(opts, :title, "Nixstasis E2E Reports")
    ref_name = Keyword.get(opts, :ref_name, "local")
    ref_type = normalize_ref_type(Keyword.get(opts, :ref_type, "branch"))
    full_sha = Keyword.get(opts, :full_sha, "local")
    short_sha = short_sha(full_sha)
    timestamp = normalize_timestamp(Keyword.get(opts, :timestamp))
    max_runs = parse_max_runs(Keyword.get(opts, :max_runs))
    is_release = release_ref?(ref_type, ref_name)
    run_path = build_run_path(ref_name, short_sha)
    run_dir = Path.join(pages_dir, run_path)

    reports = load_reports(reports_dir)
    write_shared_assets(pages_dir)
    write_run_page(run_dir, run_path, reports, logs_dir, title, timestamp, ref_name, ref_type, full_sha)

    manifest_entry = %{
      "id" => "#{ref_name}:#{full_sha}",
      "ref_name" => ref_name,
      "ref_type" => ref_type,
      "full_commit_sha" => full_sha,
      "short_commit_sha" => short_sha,
      "timestamp" => timestamp,
      "run_path" => normalize_run_path(run_path),
      "is_release" => is_release
    }

    manifest_path = Path.join(pages_dir, "runs.json")

    {manifest, purged_paths} =
      manifest_path
      |> load_manifest()
      |> upsert_manifest_entry(manifest_entry)
      |> purge_non_release_runs(max_runs)

    Enum.each(purged_paths, fn path ->
      pages_dir
      |> Path.join(path)
      |> File.rm_rf!()
    end)

    manifest =
      manifest
      |> Map.put("schema_version", @manifest_version)
      |> Map.put("generated_at", DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601())

    atomic_write_json(manifest_path, manifest)
    write_root_index(Path.join(pages_dir, "index.html"), title)

    Mix.shell().info("Exported run to #{Path.join(pages_dir, run_path)}")
    Mix.shell().info("Manifest entries: #{length(manifest["runs"] || [])}")
    if purged_paths != [], do: Mix.shell().info("Purged runs: #{length(purged_paths)}")
  end

  defp required_opt(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> Mix.raise("missing required option --#{key |> Atom.to_string() |> String.replace("_", "-")}")
    end
  end

  defp normalize_ref_type("tag"), do: "tag"
  defp normalize_ref_type(_), do: "branch"

  defp short_sha(full_sha) when is_binary(full_sha) do
    full_sha
    |> String.trim()
    |> String.slice(0, 7)
    |> case do
      "" -> "unknown"
      value -> value
    end
  end

  defp normalize_timestamp(nil) do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp normalize_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.to_iso8601(DateTime.truncate(dt, :second))
      _ -> normalize_timestamp(nil)
    end
  end

  defp parse_max_runs(nil), do: @default_max_runs

  defp parse_max_runs(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> @default_max_runs
    end
  end

  defp release_ref?("tag", ref_name), do: Regex.match?(@release_tag_regex, ref_name)
  defp release_ref?(_, _), do: false

  defp safe_ref_name(ref_name) do
    ref_name
    |> String.trim()
    |> String.replace("..", "_")
    |> String.replace("\\", "_")
    |> String.replace(~r{^/+}, "")
    |> case do
      "" -> "unknown-ref"
      value -> value
    end
  end

  defp build_run_path(ref_name, short_sha) do
    Path.join(["runs", safe_ref_name(ref_name), short_sha])
  end

  defp normalize_run_path(path), do: String.trim_trailing(path, "/") <> "/"

  defp load_reports(reports_dir) do
    reports_dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(fn file ->
      file
      |> File.read!()
      |> Jason.decode!()
      |> Map.put("_report_file", Path.basename(file))
    end)
  end

  defp write_shared_assets(pages_dir) do
    assets_dir = Path.join([pages_dir, "assets", "e2e_log_viewer"])
    File.mkdir_p!(assets_dir)
    File.cp!(@shared_viewer_js_path, Path.join(assets_dir, "viewer.js"))
    File.cp!(@shared_viewer_css_path, Path.join(assets_dir, "viewer.css"))
  end

  defp write_run_page(run_dir, run_path, reports, logs_dir, title, timestamp, ref_name, ref_type, full_sha) do
    File.rm_rf!(run_dir)
    File.mkdir_p!(run_dir)
    logs_export_dir = Path.join(run_dir, "logs")
    File.mkdir_p!(logs_export_dir)

    run_reports =
      Enum.map(reports, fn report ->
        run_id = report["RunID"] || ""
        journeys = report["Journeys"] || []

        exported_logs =
          Enum.map(journeys, fn journey ->
            journey_id = to_string(journey["JourneyID"] || "")
            log_entries = load_log_entries(logs_dir, run_id, journey_id)
            file_name = "#{journey_id}.json"
            File.write!(Path.join(logs_export_dir, file_name), Jason.encode!(%{"entries" => log_entries}, pretty: true))

            Map.put(journey, "log_payload", "logs/#{file_name}")
          end)

        report
        |> Map.put("Journeys", exported_logs)
      end)

    root_prefix = relative_root_prefix(run_path)

    run_data = %{
      "title" => title,
      "timestamp" => timestamp,
      "ref_name" => ref_name,
      "ref_type" => ref_type,
      "full_sha" => full_sha,
      "reports" => run_reports
    }

    File.write!(Path.join(run_dir, "run.json"), Jason.encode!(run_data, pretty: true))
    File.write!(Path.join(run_dir, "index.html"), run_page_html(root_prefix))
  end

  defp load_log_entries(logs_dir, run_id, journey_id) do
    path_glob = Path.join([logs_dir, run_id, "*-#{journey_id}.log"])

    case path_glob |> Path.wildcard() |> Enum.sort() |> List.first() do
      nil -> []
      path -> path |> File.read!() |> E2ELogPresenter.parse_entries()
    end
  rescue
    _ -> []
  end

  defp relative_root_prefix(run_path) do
    depth =
      run_path
      |> String.trim("/")
      |> String.split("/", trim: true)
      |> length()

    Enum.map_join(1..depth, "", fn _ -> "../" end)
  end

  defp run_page_html(root_prefix) do
    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>E2E Run</title>
      <link rel="stylesheet" href="#{root_prefix}assets/e2e_log_viewer/viewer.css" />
      <style>
        body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin: 1.5rem; background: #f5f7fb; color: #1f2937; }
        .card { background: #fff; border: 1px solid #d6deeb; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border-bottom: 1px solid #e5e7eb; padding: 0.5rem; text-align: left; vertical-align: top; }
        .journey-log { margin-top: 0.6rem; }
      </style>
    </head>
    <body>
      <p><a href="#{root_prefix}index.html">Back to all runs</a></p>
      <h1 id="run-title">E2E Run</h1>
      <div class="card" id="run-meta"></div>
      <div class="card">
        <h2>Suite Results</h2>
        <div id="run-results"></div>
      </div>
      <script src="#{root_prefix}assets/e2e_log_viewer/viewer.js"></script>
      <script>
        async function loadRun() {
          const payload = await fetch("./run.json", { cache: "no-store" }).then((r) => r.json())
          document.getElementById("run-title").textContent = `E2E Run: ${payload.ref_name} @ ${payload.full_sha.slice(0, 7)}`
          document.getElementById("run-meta").innerHTML = `
            <p><strong>Ref:</strong> ${payload.ref_type}:${payload.ref_name}</p>
            <p><strong>Commit:</strong> ${payload.full_sha}</p>
            <p><strong>Generated:</strong> ${payload.timestamp}</p>
          `

          const root = document.getElementById("run-results")
          root.innerHTML = ""

          for (const report of payload.reports) {
            const reportCard = document.createElement("div")
            reportCard.className = "card"
            reportCard.innerHTML = `<h3>Run ${report.RunID || "unknown"} (${report.Status || "unknown"})</h3>`

            const table = document.createElement("table")
            table.innerHTML = "<thead><tr><th>Journey</th><th>Status</th><th>Duration (ms)</th><th>Error</th></tr></thead><tbody></tbody>"
            const tbody = table.querySelector("tbody")

            for (const journey of report.Journeys || []) {
              const row = document.createElement("tr")
              row.innerHTML = `<td>${journey.JourneyID || ""}</td><td>${journey.Status || ""}</td><td>${journey.DurationMs ?? ""}</td><td>${journey.Error || ""}</td>`
              tbody.appendChild(row)

              const logRow = document.createElement("tr")
              const cell = document.createElement("td")
              cell.colSpan = 4
              const details = document.createElement("details")
              details.className = "journey-log"
              details.innerHTML = `<summary>Journey Log</summary><div class="journey-log-viewer"></div>`
              cell.appendChild(details)
              logRow.appendChild(cell)
              tbody.appendChild(logRow)

              try {
                const logPayload = await fetch(journey.log_payload, { cache: "no-store" }).then((r) => r.json())
                const container = details.querySelector(".journey-log-viewer")
                window.NixstasisE2ELogViewer.render(container, logPayload)
              } catch (_err) {
                details.querySelector(".journey-log-viewer").innerHTML = "<div class='text-danger'>Log unavailable</div>"
              }
            }

            reportCard.appendChild(table)
            root.appendChild(reportCard)
          }
        }
        loadRun()
      </script>
    </body>
    </html>
    """
  end

  defp load_manifest(path) do
    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"runs" => runs} = decoded} when is_list(runs) -> decoded
          _ -> %{"schema_version" => @manifest_version, "runs" => []}
        end

      _ ->
        %{"schema_version" => @manifest_version, "runs" => []}
    end
  end

  defp upsert_manifest_entry(%{"runs" => runs} = manifest, entry) do
    filtered = Enum.reject(runs, &(&1["id"] == entry["id"]))
    updated = [entry | filtered]
    Map.put(manifest, "runs", updated)
  end

  defp purge_non_release_runs(%{"runs" => runs} = manifest, max_runs) do
    purge_candidates =
      runs
      |> Enum.reject(&(&1["is_release"] == true))
      |> Enum.sort_by(fn run -> {run["timestamp"] || "", run["full_commit_sha"] || ""} end)

    overflow = max(length(purge_candidates) - max_runs, 0)
    to_purge = Enum.take(purge_candidates, overflow)
    purge_ids = MapSet.new(Enum.map(to_purge, & &1["id"]))

    kept =
      runs
      |> Enum.reject(&MapSet.member?(purge_ids, &1["id"]))
      |> Enum.sort_by(fn run -> {run["timestamp"] || "", run["full_commit_sha"] || ""} end, :desc)

    purged_paths = Enum.map(to_purge, &String.trim_trailing(&1["run_path"] || "", "/"))
    {Map.put(manifest, "runs", kept), purged_paths}
  end

  defp atomic_write_json(path, map) do
    dir = Path.dirname(path)
    File.mkdir_p!(dir)
    tmp_path = Path.join(dir, ".runs.json.tmp.#{System.unique_integer([:positive])}")
    encoded = Jason.encode!(map, pretty: true)

    {:ok, file} = :file.open(String.to_charlist(tmp_path), [:write, :binary, :raw])
    :ok = :file.write(file, encoded)
    :ok = :file.sync(file)
    :ok = :file.close(file)
    :ok = File.rename(tmp_path, path)
  end

  defp write_root_index(path, title) do
    html = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>#{title}</title>
      <style>
        body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, sans-serif; margin: 1.5rem; background: #f5f7fb; color: #1f2937; }
        .card { background: #fff; border: 1px solid #d6deeb; border-radius: 8px; padding: 1rem; margin: 1rem 0; }
        table { width: 100%; border-collapse: collapse; }
        th, td { border-bottom: 1px solid #e5e7eb; padding: 0.5rem; text-align: left; vertical-align: top; }
        .row-controls { display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 1rem; }
      </style>
    </head>
    <body>
      <h1>#{title}</h1>
      <div class="card">
        <div class="row-controls">
          <label>Ref Type
            <select id="ref-type">
              <option value="all">all</option>
              <option value="branch">branch</option>
              <option value="tag">tag</option>
            </select>
          </label>
          <label>Ref Name
            <select id="ref-name"><option value="all">all</option></select>
          </label>
        </div>
        <div id="runs-root"></div>
      </div>
      <script>
        const refTypeSelect = document.getElementById("ref-type")
        const refNameSelect = document.getElementById("ref-name")
        const root = document.getElementById("runs-root")

        function sortRuns(runs) {
          return [...runs].sort((a, b) => {
            const ts = String(b.timestamp || "").localeCompare(String(a.timestamp || ""))
            if (ts !== 0) return ts
            return String(b.full_commit_sha || "").localeCompare(String(a.full_commit_sha || ""))
          })
        }

        function render(runs) {
          const refType = refTypeSelect.value
          const refName = refNameSelect.value
          const filtered = runs.filter((run) => {
            if (refType !== "all" && run.ref_type !== refType) return false
            if (refName !== "all" && run.ref_name !== refName) return false
            return true
          })

          const grouped = {}
          for (const run of sortRuns(filtered)) {
            if (!grouped[run.ref_name]) grouped[run.ref_name] = []
            grouped[run.ref_name].push(run)
          }

          const sections = Object.keys(grouped).sort().map((name) => {
            const rows = grouped[name].map((run) => `
              <tr>
                <td><a href="${run.run_path}">${run.short_commit_sha}</a></td>
                <td>${run.ref_type}</td>
                <td>${run.timestamp}</td>
                <td>${run.is_release ? "yes" : "no"}</td>
                <td>${run.full_commit_sha}</td>
              </tr>
            `).join("")

            return `
              <h3>${name}</h3>
              <table>
                <thead><tr><th>Run</th><th>Type</th><th>Timestamp</th><th>Release</th><th>Commit</th></tr></thead>
                <tbody>${rows}</tbody>
              </table>
            `
          }).join("")

          root.innerHTML = sections || "<p>No runs available.</p>"
        }

        fetch("./runs.json", { cache: "no-store" })
          .then((r) => r.json())
          .then((manifest) => {
            const runs = manifest.runs || []
            const names = [...new Set(runs.map((run) => run.ref_name))].sort()
            for (const name of names) {
              const opt = document.createElement("option")
              opt.value = name
              opt.textContent = name
              refNameSelect.appendChild(opt)
            }
            refTypeSelect.addEventListener("change", () => render(runs))
            refNameSelect.addEventListener("change", () => render(runs))
            render(runs)
          })
          .catch(() => {
            root.innerHTML = "<p>Failed to load runs manifest.</p>"
          })
      </script>
    </body>
    </html>
    """

    File.write!(path, html)
  end
end
