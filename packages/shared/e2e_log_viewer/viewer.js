(function (global) {
  "use strict"

  function escapeHtml(input) {
    return String(input ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }

  function statusClass(status) {
    const value = String(status || "").toLowerCase()
    if (value === "passed") return "e2e-step-status-pass"
    if (value === "failed") return "e2e-step-status-fail"
    return "e2e-step-status-neutral"
  }

  function statusIcon(status) {
    return String(status || "").toLowerCase() === "passed" ? "✓" : "✕"
  }

  function responseStatusClass(code) {
    const num = Number(code)
    if (!Number.isFinite(num)) return "e2e-step-panel-status-neutral"
    if (num >= 200 && num <= 299) return "e2e-step-panel-status-pass"
    if (num >= 400 && num <= 599) return "e2e-step-panel-status-fail"
    return "e2e-step-panel-status-neutral"
  }

  function panelTitle(panel) {
    if (!panel || panel.panel_type !== "response") {
      return panel?.title || "Panel"
    }

    const bytes = Number(panel.bytes)
    if (Number.isFinite(bytes) && bytes >= 0) {
      return `${panel.title} (${bytes.toLocaleString()} bytes)`
    }
    return panel.title
  }

  function renderStepPanels(entry) {
    const panels = Array.isArray(entry.data_panels) ? entry.data_panels : []
    const hasMetadata = !!entry.metadata_pretty

    if (panels.length === 0 && !hasMetadata) {
      return ""
    }

    const metadataPanel = hasMetadata
      ? `
        <details class="e2e-step-panel" data-details-key="metadata|${escapeHtml(entry.timestamp)}">
          <summary><span class="e2e-step-panel-summary-left">Metadata</span></summary>
          <div class="e2e-step-panel-body"><pre class="text-monospace e2e-step-data-pre">${escapeHtml(entry.metadata_pretty)}</pre></div>
        </details>
      `
      : ""

    const panelHtml = panels
      .map((panel, idx) => {
        const right =
          panel.http_status != null
            ? `<span class="e2e-step-panel-summary-right">
                <span class="e2e-step-panel-status ${responseStatusClass(panel.http_status)}">${escapeHtml(panel.http_status)}</span>
                <span class="e2e-step-panel-beer">${panel.truncated ? "◐" : "●"}</span>
              </span>`
            : ""

        return `
          <details class="e2e-step-panel" data-details-key="panel|${escapeHtml(entry.timestamp)}|${idx}">
            <summary>
              <span class="e2e-step-panel-summary-left">${escapeHtml(panelTitle(panel))}</span>
              ${right}
            </summary>
            <div class="e2e-step-panel-body"><pre class="text-monospace e2e-step-data-pre">${escapeHtml(panel.pretty || "")}</pre></div>
          </details>
        `
      })
      .join("")

    return `
      <div class="e2e-step-panels-shell">
        <hr class="e2e-step-panels-divider" />
        <div class="e2e-step-panels-stack">
          ${metadataPanel}
          ${panelHtml}
        </div>
      </div>
    `
  }

  function renderSummary(entry) {
    const summary = entry.summary || {}
    const totalDuration = Number(summary.total_duration_ms)
    const durationText = Number.isFinite(totalDuration)
      ? totalDuration >= 1000
        ? `${(totalDuration / 1000).toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} s`
        : `${Math.round(totalDuration).toLocaleString()} ms`
      : "—"

    return `
      <table class="e2e-summary-table">
        <thead>
          <tr><th>Start</th><th>End</th><th>Total Duration</th><th>Passed</th><th>Failed</th><th>Total</th></tr>
        </thead>
        <tbody>
          <tr>
            <td>${escapeHtml(summary.start_at || "—")}</td>
            <td>${escapeHtml(summary.end_at || "—")}</td>
            <td>${escapeHtml(durationText)}</td>
            <td>${escapeHtml(summary.passed_count ?? 0)}</td>
            <td>${escapeHtml(summary.failed_count ?? 0)}</td>
            <td>${escapeHtml(summary.total_count ?? 0)}</td>
          </tr>
        </tbody>
      </table>
    `
  }

  function renderInfo(entry) {
    const payload = entry.payload_pretty
      ? `<details class="e2e-step-panel" data-details-key="info|${escapeHtml(entry.timestamp)}">
          <summary>${escapeHtml(entry.payload_label || "Raw payload")}</summary>
          <div class="e2e-step-panel-body"><pre class="text-monospace e2e-step-data-pre">${escapeHtml(entry.payload_pretty)}</pre></div>
        </details>`
      : ""

    return `
      <pre class="text-monospace e2e-info-pre">${escapeHtml(entry.message || "")}</pre>
      ${payload}
    `
  }

  function renderStepHeader(entry) {
    const header = entry.step_header || {}
    return `
      <table class="e2e-step-header-table">
        <tbody>
          <tr>
            <td><div class="e2e-step-kv"><span class="e2e-step-key">Action:</span><span class="e2e-step-value">${escapeHtml(header.action || "—")}</span></div></td>
            <td><div class="e2e-step-kv"><span class="e2e-step-key">Expected:</span><span class="e2e-step-value">${escapeHtml(header.expected || "—")}</span></div></td>
            <td class="e2e-step-status-col"><span class="e2e-step-status-icon ${statusClass(header.status)}">${statusIcon(header.status)}</span></td>
          </tr>
        </tbody>
      </table>
    `
  }

  function rowClass(entry, index) {
    const classes = ["e2e-log-entry", `e2e-log-entry-${entry.kind}`]
    if (index % 2 === 0) classes.push("e2e-log-entry-even")
    if (entry.kind === "summary") {
      classes.push(entry.status === "failed" ? "e2e-log-summary-failed" : "e2e-log-summary-passed")
    }
    return classes.join(" ")
  }

  function badgeClass(entry) {
    if (entry.kind === "start") return "e2e-log-badge-start"
    if (entry.kind === "step" && entry.status === "failed") return "e2e-log-badge-failed"
    if (entry.kind === "step") return "e2e-log-badge-step"
    if (entry.kind === "summary") return "e2e-log-badge-summary"
    return "e2e-log-badge-info"
  }

  function formatDuration(ms) {
    const value = Number(ms)
    if (!Number.isFinite(value)) return ""
    if (Math.abs(value) < 1000) return `${Math.round(value).toLocaleString()} ms`
    return `${(value / 1000).toLocaleString(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 })} s`
  }

  function renderEntry(entry, idx) {
    const duration = entry.kind === "step" ? `<div class="e2e-log-duration">${escapeHtml(formatDuration(entry.duration_ms))}</div>` : ""
    let body = ""

    if (entry.kind === "step") {
      body = `${renderStepHeader(entry)}${renderStepPanels(entry)}`
    } else if (entry.kind === "summary") {
      body = renderSummary(entry)
    } else {
      body = renderInfo(entry)
    }

    return `
      <div class="${rowClass(entry, idx)}">
        <div class="e2e-log-rail">
          <span class="e2e-log-badge ${badgeClass(entry)}">${escapeHtml(entry.icon_label || "INFO")}</span>
          ${duration}
        </div>
        <div class="e2e-log-content">
          <div class="text-muted e2e-log-timestamp">${escapeHtml(entry.timestamp || "")}</div>
          ${body}
        </div>
      </div>
    `
  }

  function render(container, payload) {
    if (!container) return
    const entries = Array.isArray(payload?.entries) ? payload.entries : []
    container.innerHTML = entries.map(renderEntry).join("")
  }

  global.NixstasisE2ELogViewer = { render }
})(window)
