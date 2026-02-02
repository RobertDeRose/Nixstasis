# Research: IoT Dashboard Homepage

**Feature**: `002-add-dashboard-home`

## Unknowns & Clarifications

### 1. Data Refresh Mechanism
- **Question**: How should the dashboard data be refreshed?
- **Research**: Evaluated Polling vs LiveView.
- **Decision**: **Real-time via LiveView**.
- **Rationale**: Phoenix LiveView makes real-time updates trivial via PubSub. It provides a superior UX ("User Experience First" constitution principle) compared to polling, with minimal implementation overhead in the Elixir ecosystem.
- **Alternatives**:
  - *Polling*: Simpler to implement initially but less responsive and can be chatty.
  - *WebSockets (manual)*: Too complex compared to LiveView abstraction.

### 2. Historical Context
- **Question**: What historical context should be shown for the vital stats?
- **Research**: Considered showing trends (sparklines) vs simple snapshots.
- **Decision**: **Snapshot Only**.
- **Rationale**: "Quality & Simplicity" principle. The primary goal is immediate situational awareness. Storing and querying historical time-series data adds significant complexity (new tables, aggregations) not justified for the MVP homepage.
- **Alternatives**:
  - *Trend Lines*: Requires querying `telemetry_events` or a separate `stats_history` table. Deferred to future feature.

### 3. Permissions/RBAC
- **Question**: How should user permissions affect dashboard visibility?
- **Research**: Checked existing auth implementation.
- **Decision**: **Single Role (All Visible)**.
- **Rationale**: Keeps scope focused on the dashboard functionality. RBAC is a cross-cutting concern to be handled separately. "Simple implementation when feasible".
- **Alternatives**:
  - *RBAC*: Would require implementing a permissions system if one doesn't exist, which expands scope significantly.

## Technical approach

### Aggregation Strategy
- Use direct `count(*)` queries on `devices` and `alerts` tables.
- **Performance Note**: For an MVP with < 100k devices, this is instant in Postgres. If scale increases, we can introduce a cached counter or `estimated_count` strategy later.

### Real-time Strategy
- Leverage `Phoenix.PubSub`.
- `Nixstasis.Devices` context will broadcast on `devices` topic when a device registers or changes status.
- `Nixstasis.Alerts` context will broadcast on `alerts` topic when an alert is created/resolved.
- `DashboardLive` will subscribe to these topics and re-fetch specific stats on relevant messages.
