# Shared E2E Log Viewer

## Language

- JavaScript and CSS.

## Runtime Context

- Shared static assets for E2E log viewing/report output.

## Purpose

- Provides client-side static viewer behavior and styling for exported E2E logs/pages.

## Key Files

- `packages/shared/e2e_log_viewer/viewer.js`
- `packages/shared/e2e_log_viewer/viewer.css`
- `.github/workflows/e2e-pages.yml`
- `packages/server/lib/mix/tasks/e2e.export_static.ex`

## Public Interfaces

- Static asset files consumed by E2E report/export workflows.

## Dependencies

### Internal

- Server E2E static export Mix task.
- GitHub Pages E2E workflow.

### External

- Browser JavaScript and CSS runtime.

## Client-Server Interaction Details

- Exported static pages are generated from E2E run data and logs.
- The root E2E Pages index loads `runs.json` client-side according to repository README documentation.

Traceable references:
- `README.md:187-203`
- `packages/shared/e2e_log_viewer/viewer.js`
- `packages/shared/e2e_log_viewer/viewer.css`
