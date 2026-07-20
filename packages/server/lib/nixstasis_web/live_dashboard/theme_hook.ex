defmodule NixstasisWeb.LiveDashboard.ThemeHook do
  @moduledoc false

  import Phoenix.Component

  alias Phoenix.LiveDashboard.PageBuilder

  @shared_viewer_js_path Path.expand("../../../../shared/e2e_log_viewer/viewer.js", __DIR__)
  @shared_viewer_css_path Path.expand("../../../../shared/e2e_log_viewer/viewer.css", __DIR__)
  @external_resource @shared_viewer_js_path
  @external_resource @shared_viewer_css_path
  @shared_viewer_js File.read!(@shared_viewer_js_path)
  @shared_viewer_css File.read!(@shared_viewer_css_path)

  def on_mount(:default, _params, _session, socket) do
    socket =
      socket
      |> PageBuilder.register_after_opening_head_tag(&after_opening_head_tag/1)
      |> PageBuilder.register_before_closing_head_tag(&before_closing_head_tag/1)

    {:cont, socket}
  end

  defp after_opening_head_tag(assigns) do
    assigns = assign(assigns, :shared_viewer_js, @shared_viewer_js)

    ~H"""
    <script nonce={@csp_nonces[:script]}>
      <%= Phoenix.HTML.raw(@shared_viewer_js) %>

      window.LiveDashboard.registerCustomHooks({
        SharedE2ELogViewer: {
          mounted() {
            this.render()
          },
          updated() {
            this.render()
          },
          render() {
            if (!window.NixstasisE2ELogViewer) {
              return
            }

            const encoded = this.el.dataset.logPayload || ""
            if (!encoded) {
              this.el.innerHTML = ""
              return
            }

            try {
              const decoded = window.atob(encoded)
              const payload = JSON.parse(decoded)
              window.NixstasisE2ELogViewer.render(this.el, payload)
            } catch (_err) {
              this.el.innerHTML = "<div class=\"text-danger\">Failed to render journey log.</div>"
            }
          }
        },
        IndeterminateCheckbox: {
          mounted() {
            this.updateState()
          },
          updated() {
            this.updateState()
          },
          updateState() {
            const selectedCount = parseInt(this.el.dataset.selectedCount) || 0
            const totalCount = parseInt(this.el.dataset.totalCount) || 0

            if (selectedCount === 0) {
              this.el.checked = false
              this.el.indeterminate = false
            } else if (selectedCount === totalCount && totalCount > 0) {
              this.el.checked = true
              this.el.indeterminate = false
            } else {
              this.el.checked = false
              this.el.indeterminate = true
            }
          }
        },
        PersistDetailsState: {
          mounted() {
            this.openKeys = new Set()
            this.restoreOpenState()
          },
          beforeUpdate() {
            this.captureOpenState()
          },
          updated() {
            this.restoreOpenState()
          },
          captureOpenState() {
            this.openKeys = new Set(
              Array.from(this.el.querySelectorAll("details[data-details-key][open]"))
                .map((details) => details.dataset.detailsKey)
            )
          },
          restoreOpenState() {
            if (!this.openKeys) {
              return
            }

            this.el.querySelectorAll("details[data-details-key]").forEach((details) => {
              details.open = this.openKeys.has(details.dataset.detailsKey)
            })
          }
        },
        PairDetailsPanels: {
          mounted() {
            this.bind()
          },
          updated() {
            this.bind()
          },
          destroyed() {
            this.unbind()
          },
          bind() {
            this.unbind()
            this.syncing = false
            this.listeners = []

            const detailsElements = Array.from(this.el.querySelectorAll("details[data-pair-group]"))

            detailsElements.forEach((details) => {
              const handler = () => {
                if (this.syncing) {
                  return
                }

                const group = details.dataset.pairGroup
                if (!group) {
                  return
                }

                this.syncing = true
                detailsElements.forEach((peer) => {
                  if (peer === details || peer.dataset.pairGroup !== group) {
                    return
                  }
                  peer.open = details.open
                })
                this.syncing = false
              }

              details.addEventListener("toggle", handler)
              this.listeners.push([details, handler])
            })
          },
          unbind() {
            if (!this.listeners) {
              return
            }

            this.listeners.forEach(([details, handler]) => {
              details.removeEventListener("toggle", handler)
            })
            this.listeners = []
          }
        },
        LocaleDuration: {
          mounted() {
            this.format()
          },
          updated() {
            this.format()
          },
          format() {
            const durationMs = Number(this.el.dataset.durationMs)
            if (!Number.isFinite(durationMs)) {
              return
            }

            if (Math.abs(durationMs) < 1000) {
              const formatter = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 })
              this.el.textContent = `${formatter.format(Math.round(durationMs))} ms`
              return
            }

            const formatter = new Intl.NumberFormat(undefined, {
              minimumFractionDigits: 1,
              maximumFractionDigits: 1
            })
            this.el.textContent = `${formatter.format(durationMs / 1000)} s`
          }
        },
        ScrollIntoViewOnMount: {
          mounted() {
            window.requestAnimationFrame(() => {
              const yOffset = 96
              const top = this.el.getBoundingClientRect().top + window.pageYOffset - yOffset
              window.scrollTo({ top, behavior: "smooth" })
            })
          }
        }
      })
    </script>
    """
  end

  defp before_closing_head_tag(assigns) do
    assigns = assign(assigns, :shared_viewer_css, @shared_viewer_css)

    ~H"""
    <style nonce={@csp_nonces[:style]}>
      <%= Phoenix.HTML.raw(@shared_viewer_css) %>

      :root {
        --ow-dash-base-100: #f4fbfd;
        --ow-dash-base-200: #e8f6f8;
        --ow-dash-base-300: #b6dce1;
        --ow-dash-base-content: #183242;
        --ow-dash-primary: #087f92;
        --ow-dash-secondary: #168fac;
        --ow-dash-accent: #18b9aa;
        --ow-dash-primary-strong: #065f67;
        --ow-dash-selection-bg: #d7f0f2;
        --ow-dash-selection-border: #18b9aa;
        --ow-dash-selection-text: #065f67;
        --primary: #087f92;
        --secondary: #168fac;
      }

      body {
        background-color: var(--ow-dash-base-200);
        color: var(--ow-dash-base-content);
        font-family: "Noto Sans", -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }

      a {
        color: var(--ow-dash-secondary);
      }

      a:hover {
        color: var(--ow-dash-primary-strong);
      }

      header {
        background: linear-gradient(135deg, var(--ow-dash-primary), var(--ow-dash-secondary));
      }

      header h1 {
        color: #ffffff;
        text-shadow: none;
        font-weight: 700;
      }

      #menu-bar {
        background-color: var(--ow-dash-base-100);
        border: 1px solid rgba(141, 159, 176, 0.35);
        box-shadow: 0 2px 8px rgba(44, 57, 71, 0.18);
      }

      #menu-bar .menu-item {
        color: var(--ow-dash-primary);
      }

      #menu-bar .menu-item:hover,
      #menu-bar .menu-item.active {
        color: var(--ow-dash-secondary);
        text-shadow: none;
      }

      #menu-bar .menu-item-enable-button {
        background-color: var(--ow-dash-secondary);
        color: #ffffff;
      }

      #nav-dropdowns label {
        color: #ffffff;
      }

      #nav-dropdowns .custom-select,
      .custom-select {
        background-color: var(--ow-dash-base-200);
        border: 1px solid rgba(141, 159, 176, 0.5);
        color: var(--ow-dash-base-content);
      }

      .form-control {
        background-color: var(--ow-dash-base-100);
        border: 1px solid rgba(141, 159, 176, 0.55);
        color: var(--ow-dash-base-content);
      }

      .form-control:focus,
      .custom-select:focus {
        border-color: var(--ow-dash-accent);
        box-shadow: 0 0 0 0.15rem rgba(141, 159, 176, 0.25);
      }

      .card,
      .tabular-card,
      .banner-card {
        background-color: var(--ow-dash-base-100);
        border: 1px solid rgba(141, 159, 176, 0.28);
        box-shadow: 0 2px 8px rgba(44, 57, 71, 0.12);
      }

      .card-title,
      .tabular th {
        color: var(--ow-dash-base-content);
      }

      .dash-table-wrapper {
        border: 1px solid rgba(141, 159, 176, 0.35);
        border-radius: 8px;
        background-color: var(--ow-dash-base-100);
      }

      .dash-table thead th {
        background-color: var(--ow-dash-primary);
        color: #ffffff;
        border-bottom: 1px solid var(--ow-dash-primary-strong);
        font-size: 0.86rem;
        font-weight: 700;
      }

      .table thead th {
        background-color: var(--ow-dash-primary) !important;
        color: #ffffff !important;
        border-bottom: 1px solid var(--ow-dash-primary-strong) !important;
      }

      .dash-table thead th a {
        color: #ffffff;
      }

      .table thead th a {
        color: #ffffff !important;
      }

      .dash-table thead th a:hover {
        color: #f3efe4;
        text-decoration: none;
      }

      .dash-table tbody td {
        border-top: 1px solid rgba(141, 159, 176, 0.25);
        color: var(--ow-dash-base-content);
      }

      .table tbody td {
        color: var(--ow-dash-base-content);
      }

      .dash-table tbody tr:nth-child(even) {
        background-color: rgba(141, 159, 176, 0.08);
      }

      .table-hover tbody tr:hover {
        background-color: rgba(141, 159, 176, 0.16) !important;
      }

      .table-hover .active {
        background-color: rgba(44, 57, 71, 0.16) !important;
      }

      .nav-pills .nav-link {
        color: var(--ow-dash-primary);
        border: 1px solid rgba(141, 159, 176, 0.45);
        margin-right: 0.35rem;
      }

      .nav-pills .nav-link:hover {
        background-color: rgba(141, 159, 176, 0.12);
        border-color: rgba(141, 159, 176, 0.6);
        color: var(--ow-dash-primary-strong);
      }

      .nav-pills .nav-link.active,
      .nav-pills .show > .nav-link {
        background-color: var(--ow-dash-primary) !important;
        border-color: var(--ow-dash-primary) !important;
        color: #ffffff !important;
      }

      .btn-primary,
      .btn.btn-primary,
      button.btn-primary,
      button.btn.btn-primary {
        background-color: var(--ow-dash-primary) !important;
        border-color: var(--ow-dash-primary) !important;
        color: #ffffff !important;
      }

      .btn-primary:hover,
      .btn-primary:focus,
      .btn-primary:not(:disabled):not(.disabled):active,
      .btn.btn-primary:hover,
      .btn.btn-primary:focus,
      .btn.btn-primary:not(:disabled):not(.disabled):active {
        background-color: var(--ow-dash-primary-strong) !important;
        border-color: var(--ow-dash-primary-strong) !important;
        color: #ffffff !important;
      }

      .btn-secondary,
      .btn.btn-secondary,
      button.btn-secondary,
      button.btn.btn-secondary {
        background-color: var(--ow-dash-secondary) !important;
        border-color: var(--ow-dash-secondary) !important;
        color: #ffffff !important;
      }

      .btn-secondary:hover,
      .btn-secondary:focus,
      .btn-secondary:not(:disabled):not(.disabled):active,
      .btn.btn-secondary:hover,
      .btn.btn-secondary:focus,
      .btn.btn-secondary:not(:disabled):not(.disabled):active {
        background-color: var(--ow-dash-primary-strong) !important;
        border-color: var(--ow-dash-primary-strong) !important;
        color: #ffffff !important;
      }

      .btn-link {
        color: var(--ow-dash-secondary);
      }

      .btn-link:hover {
        color: var(--ow-dash-primary-strong);
      }

      .code-field {
        background-color: var(--ow-dash-base-100);
        border: 1px solid var(--ow-dash-base-300);
        color: var(--ow-dash-base-content);
        border-radius: 6px;
      }

      .copy-indicator {
        color: var(--ow-dash-secondary);
        font-weight: 600;
      }

      .cookie-status {
        color: var(--ow-dash-base-content);
      }

      .cookie-status::before {
        background-color: var(--ow-dash-secondary);
      }

      .logs-card #logger-messages pre {
        color: var(--ow-dash-base-content);
      }

      .logs-card #logger-messages pre:hover {
        background-color: rgba(141, 159, 176, 0.14);
      }

      .nav-bar {
        background-color: var(--ow-dash-base-200);
      }

      .nav-bar .nav-link.active {
        border-bottom-color: var(--ow-dash-secondary);
        color: var(--ow-dash-secondary);
      }

      .nav-bar .nav-link.active {
        border-bottom-color: var(--ow-dash-secondary) !important;
        color: var(--ow-dash-secondary) !important;
      }

      .bg-purple {
        background-color: var(--ow-dash-primary) !important;
      }

      .bg-gradient-purple {
        background: linear-gradient(40deg, var(--ow-dash-primary), var(--ow-dash-secondary)) !important;
      }

      .hint:hover .hint-text {
        background-color: var(--ow-dash-base-100);
        border-color: rgba(141, 159, 176, 0.45);
        color: var(--ow-dash-base-content);
      }

      .hint .hint-text {
        min-width: 22rem;
        max-width: 44rem;
        white-space: normal;
        overflow-wrap: anywhere;
        word-break: break-word;
      }

      #e2e-filters-card .banner-card-value {
        font-size: 1rem;
        font-weight: 400;
      }

      #e2e-results-table .banner-card-value {
        font-size: 1rem;
        font-weight: 400;
      }

      #e2e-filters-form {
        margin: 0;
      }

      #e2e-filters-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(170px, 1fr));
        gap: 0.85rem 1rem;
        align-items: end;
      }

      #e2e-filters-card .e2e-filter-group label {
        display: block;
        margin-bottom: 0.3rem;
        font-size: 0.76rem;
        font-weight: 700;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        color: #546474;
      }

      #e2e-filters-card .e2e-filter-group .custom-select {
        width: 100%;
        min-height: 34px;
        font-size: 0.92rem;
      }

      #e2e-filters-card .e2e-filters-help {
        font-size: 0.87rem;
        line-height: 1.3;
        color: #5b6c7e;
      }

      #e2e-filters-card .e2e-filters-footer {
        margin-top: 0.8rem;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 1rem;
        flex-wrap: wrap;
      }

      #e2e-filters-card .e2e-run-actions {
        display: inline-flex;
        align-items: center;
        gap: 0.6rem;
      }

      #e2e-filters-card .e2e-run-actions .text-muted {
        font-size: 0.86rem;
        font-weight: 600;
      }

      .e2e-run-select-checkbox {
        cursor: pointer;
      }

      .e2e-runs-table-selected {
        width: 44px;
        text-align: center;
      }

      #e2e-runs-table .e2e-run-active td,
      #e2e-runs-table .e2e-run-active td a {
        color: var(--ow-dash-selection-text) !important;
        font-weight: 700 !important;
      }

      #e2e-runs-table .e2e-run-active {
        background-color: var(--ow-dash-selection-bg) !important;
        box-shadow: inset 3px 0 0 var(--ow-dash-selection-border);
      }

      #e2e-results-table .e2e-parent-row {
        cursor: pointer;
      }

      #e2e-results-table .e2e-expand-indicator {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 1.2rem;
        color: #4f6378;
        margin-right: 0.1rem;
      }

      #e2e-results-table .e2e-chevron-icon {
        width: 0.9rem;
        height: 0.9rem;
      }

      #e2e-results-table .e2e-chevron-icon path {
        stroke: currentColor;
        stroke-width: 2;
        fill: none;
        stroke-linecap: round;
        stroke-linejoin: round;
      }

      #e2e-results-table .e2e-child-row > td {
        padding: 0.25rem 0.75rem 0.75rem;
        border-top: 0;
        background-color: rgba(141, 159, 176, 0.08);
      }

      #e2e-results-table .e2e-child-container {
        margin-left: 1.35rem;
        padding: 0.75rem 0.85rem;
        border-left: 3px solid rgba(44, 57, 71, 0.5);
        border-radius: 6px;
        border: 1px solid rgba(141, 159, 176, 0.32);
        background-color: var(--ow-dash-base-100);
      }

      #e2e-results-table .e2e-child-empty {
        font-size: 0.95rem;
      }

      #e2e-results-table .e2e-child-table thead th {
        font-size: 0.86rem;
        font-weight: 700;
        letter-spacing: normal;
        text-transform: none;
        background-color: rgba(141, 159, 176, 0.16) !important;
        color: var(--ow-dash-base-content) !important;
        border-bottom: 1px solid rgba(141, 159, 176, 0.5) !important;
      }

      #e2e-results-table .e2e-child-table tbody td {
        font-size: 1rem;
        font-weight: 400;
        font-style: normal;
      }

      #e2e-results-table .e2e-child-table tbody tr:nth-child(even) {
        background-color: rgba(141, 159, 176, 0.06);
      }

      #e2e-results-table .e2e-inline-log {
        margin-top: 0.85rem;
      }

      #e2e-results-table .e2e-inline-log-header {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 0.5rem;
        margin-bottom: 0.45rem;
      }

      #e2e-results-table .e2e-inline-log-meta {
        font-size: 0.8rem;
        overflow-wrap: anywhere;
      }

      #e2e-results-table .e2e-inline-log-entries {
        display: flex;
        flex-direction: column;
        gap: 0.55rem;
        max-height: none;
        overflow: visible;
      }

      #e2e-results-table .e2e-log-entry {
        display: grid;
        grid-template-columns: 6.25rem minmax(0, 1fr);
        gap: 0.8rem;
        border: 1px solid rgba(141, 159, 176, 0.35);
        border-radius: 8px;
        padding: 0.55rem 0.7rem;
        background-color: rgba(141, 159, 176, 0.06);
      }

      #e2e-results-table .e2e-log-entry-even {
        background-color: rgba(141, 159, 176, 0.12);
      }

      #e2e-results-table .e2e-log-rail {
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 0.4rem;
      }

      #e2e-results-table .e2e-log-badge {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        min-width: 5.7rem;
        padding: 0.2rem 0.55rem;
        border-radius: 5px;
        font-size: 0.78rem;
        font-weight: 700;
        letter-spacing: 0.06em;
        color: #fff;
      }

      #e2e-results-table .e2e-log-badge-start {
        background-color: #0284c7;
      }

      #e2e-results-table .e2e-log-badge-step {
        background-color: #2563eb;
      }

      #e2e-results-table .e2e-log-badge-summary {
        background-color: #16a34a;
      }

      #e2e-results-table .e2e-log-badge-failed {
        background-color: #dc2626;
      }

      #e2e-results-table .e2e-log-badge-info {
        background-color: #475569;
      }

      #e2e-results-table .e2e-log-duration {
        color: #536273;
        font-size: 0.86rem;
        font-style: italic;
        font-weight: 500;
      }

      #e2e-results-table .e2e-log-content {
        min-width: 0;
      }

      #e2e-results-table .e2e-log-timestamp {
        font-size: 0.84rem;
        margin-bottom: 0.32rem;
      }

      #e2e-results-table .e2e-step-header-table {
        width: 100%;
        margin: 0;
        table-layout: fixed;
      }

      #e2e-results-table .e2e-step-header-table td {
        padding: 0.08rem 0.45rem 0.08rem 0;
        border: 0;
        vertical-align: middle;
      }

      #e2e-results-table .e2e-step-header-table td:nth-child(1),
      #e2e-results-table .e2e-step-header-table td:nth-child(2) {
        width: 44%;
      }

      #e2e-results-table .e2e-step-header-table td:nth-child(3) {
        width: 12%;
      }

      #e2e-results-table .e2e-step-kv {
        display: grid;
        grid-template-columns: 5.3rem minmax(0, 1fr);
        align-items: center;
        gap: 0.45rem;
      }

      #e2e-results-table .e2e-step-key {
        text-align: right;
        font-size: 1rem;
        font-weight: 700;
        color: #4f6378;
      }

      #e2e-results-table .e2e-step-value {
        text-align: left;
        font-size: 1rem;
        color: var(--ow-dash-base-content);
        overflow-wrap: anywhere;
        word-break: break-word;
      }

      #e2e-results-table .e2e-step-status-col {
        width: 2.4rem;
        text-align: center;
      }

      #e2e-results-table .e2e-step-status-icon {
        display: inline-block;
        font-size: 1.05rem;
        font-weight: 700;
        line-height: 1;
      }

      #e2e-results-table .e2e-step-status-pass {
        color: #0f9f58;
      }

      #e2e-results-table .e2e-step-status-fail {
        color: #c0262d;
      }

      #e2e-results-table .e2e-step-status-neutral {
        color: #66788b;
      }

      #e2e-results-table .e2e-step-panels-shell {
        margin-top: 0.35rem;
      }

      #e2e-results-table .e2e-step-panels-divider {
        border: 0;
        border-top: 1px solid rgba(141, 159, 176, 0.35);
        margin: 0.45rem 0 0.5rem;
      }

      #e2e-results-table .e2e-step-panels-stack {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      #e2e-results-table .e2e-step-panel {
        margin: 0;
        border: 1px solid rgba(141, 159, 176, 0.34);
        border-radius: 6px;
        background-color: rgba(255, 255, 255, 0.7);
        overflow: hidden;
      }

      #e2e-results-table .e2e-step-panel summary {
        display: list-item;
        cursor: pointer;
        padding: 0.38rem 0.55rem;
        font-size: 0.84rem;
        font-weight: 700;
        color: #4b5f73;
        background-color: rgba(141, 159, 176, 0.18);
        user-select: none;
      }

      #e2e-results-table .e2e-step-panel-summary-left {
        display: inline;
        min-width: 0;
        overflow-wrap: anywhere;
      }

      #e2e-results-table .e2e-step-panel-summary-right {
        float: right;
        display: inline-flex;
        align-items: center;
        gap: 0.35rem;
        margin-left: 0.65rem;
      }

      #e2e-results-table .e2e-step-panel summary::after {
        content: "";
        display: block;
        clear: both;
      }

      #e2e-results-table .e2e-step-panel-status {
        font-weight: 800;
      }

      #e2e-results-table .e2e-step-panel-status-success {
        color: #0f9f58;
      }

      #e2e-results-table .e2e-step-panel-status-error {
        color: #c0262d;
      }

      #e2e-results-table .e2e-step-panel-status-neutral {
        color: #607080;
      }

      #e2e-results-table .e2e-step-panel-beer {
        font-size: 0.95rem;
        line-height: 1;
        color: #4f6378;
      }

      #e2e-results-table .e2e-step-panel-body {
        padding: 0.42rem 0.55rem 0.5rem;
      }

      #e2e-results-table .e2e-step-data-block + .e2e-step-data-block {
        margin-top: 0.65rem;
      }

      #e2e-results-table .e2e-step-data-label {
        font-size: 0.8rem;
        font-weight: 700;
        color: #5f7082;
        margin-bottom: 0.22rem;
      }

      #e2e-results-table .e2e-step-data-pre {
        margin: 0;
        font-size: 0.84rem;
        line-height: 1.32;
        white-space: pre-wrap;
        word-break: break-word;
      }

      #e2e-results-table .e2e-summary-table {
        width: 100%;
        margin: 0;
      }

      #e2e-results-table .e2e-summary-table th,
      #e2e-results-table .e2e-summary-table td {
        border: 0;
        padding: 0.2rem 0.3rem;
        font-size: 0.88rem;
        text-align: left;
      }

      #e2e-results-table .e2e-summary-table th {
        font-size: 0.78rem;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        color: #536273;
      }

      #e2e-results-table .e2e-log-summary-passed {
        border-color: rgba(22, 163, 74, 0.46);
        background: linear-gradient(90deg, rgba(22, 163, 74, 0.2), rgba(22, 163, 74, 0.06));
      }

      #e2e-results-table .e2e-log-summary-failed {
        border-color: rgba(220, 38, 38, 0.46);
        background: linear-gradient(90deg, rgba(220, 38, 38, 0.2), rgba(220, 38, 38, 0.06));
      }

      .e2e-modal-backdrop {
        position: fixed;
        inset: 0;
        background-color: rgba(30, 41, 59, 0.55);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 1rem;
        z-index: 1200;
      }

      .e2e-modal-card {
        width: min(460px, 96vw);
        background: var(--ow-dash-base-100);
        border: 1px solid rgba(141, 159, 176, 0.45);
        border-radius: 10px;
        box-shadow: 0 16px 48px rgba(44, 57, 71, 0.25);
        padding: 1rem 1.1rem;
      }

      .e2e-modal-card h3 {
        margin: 0;
        font-size: 1.05rem;
        font-weight: 700;
        color: var(--ow-dash-primary);
      }

      .e2e-modal-card p {
        margin: 0.65rem 0 0;
        color: var(--ow-dash-base-content);
      }

      .e2e-modal-actions {
        margin-top: 1rem;
        display: flex;
        justify-content: flex-end;
        gap: 0.6rem;
      }

      @media (max-width: 1100px) {
        #e2e-filters-grid {
          grid-template-columns: repeat(2, minmax(170px, 1fr));
        }
      }

      @media (max-width: 992px) {
        .tabular-card {
          margin-left: 0 !important;
          margin-right: 0 !important;
          border-radius: 8px !important;
        }

        .tabular {
          font-size: 0.95rem;
        }

        #e2e-filters-card,
        #e2e-results-table,
        #e2e-runs-table {
          width: 100%;
        }

      }

      @media (max-width: 1024px) {
        #e2e-results-table .e2e-log-entry {
          grid-template-columns: 1fr;
          gap: 0.45rem;
        }

        #e2e-results-table .e2e-log-rail {
          flex-direction: row;
          align-items: center;
          justify-content: flex-start;
          gap: 0.6rem;
        }

        #e2e-results-table .e2e-step-header-table,
        #e2e-results-table .e2e-step-header-table tbody,
        #e2e-results-table .e2e-step-header-table tr,
        #e2e-results-table .e2e-step-header-table td {
          display: block;
          width: 100%;
        }

        #e2e-results-table .e2e-step-header-table td {
          padding: 0.12rem 0;
          width: 100% !important;
        }

        #e2e-results-table .e2e-step-kv {
          grid-template-columns: 4.4rem minmax(0, 1fr);
          gap: 0.35rem;
        }

        #e2e-results-table .e2e-step-status-col {
          text-align: left;
          width: auto;
        }
      }

      @media (max-width: 640px) {
        #e2e-filters-grid {
          grid-template-columns: 1fr;
        }

        #e2e-filters-card .e2e-filters-footer {
          align-items: stretch;
        }

        #e2e-filters-card .e2e-run-actions {
          justify-content: space-between;
        }
      }
    </style>
    """
  end
end
