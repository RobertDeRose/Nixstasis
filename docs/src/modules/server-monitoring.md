# Server Monitoring

## Language

- Elixir.

## Runtime Context

- Server context, Ash resources, and periodic worker.

## Purpose

- Processes device heartbeats, persists telemetry events, evaluates alert rules, creates alerts, checks offline devices, and provides alert/rule APIs for LiveView screens.

## Key Files

- `packages/server/lib/nixstasis/monitoring.ex`
- `packages/server/lib/nixstasis/monitoring/offline_checker.ex`
- `packages/server/lib/nixstasis/monitoring/rule_evaluator.ex`
- `packages/server/lib/nixstasis/monitoring/telemetry.ex`
- `packages/server/lib/nixstasis/monitoring/alert.ex`
- `packages/server/lib/nixstasis/monitoring/alert_rule.ex`
- `packages/server/lib/nixstasis_web/live/alerts/index_live.ex`
- `packages/server/lib/nixstasis_web/live/alerts/rules_live.ex`

## Public Interfaces

- `Nixstasis.Monitoring.heartbeat/2`
- `Nixstasis.Monitoring.check_offline_devices/1`
- `Nixstasis.Monitoring.evaluate_telemetry/2`
- `Nixstasis.Monitoring.list_rules/0`
- `Nixstasis.Monitoring.get_rule!/1`
- `Nixstasis.Monitoring.create_rule/1`
- `Nixstasis.Monitoring.update_rule/2`
- `Nixstasis.Monitoring.delete_rule/1`
- `Nixstasis.Monitoring.list_rules_for_product/1`
- `Nixstasis.Monitoring.OfflineChecker.start_link/1`

## Dependencies

### Internal

- `Nixstasis.Devices`
- `Nixstasis.Domain`
- `Nixstasis.Settings`
- `Nixstasis.Monitoring.RuleEvaluator`
- `Nixstasis.Monitoring.Alert`
- `Nixstasis.Monitoring.AlertRule`

### External

- Ash
- GenServer

## Client-Server Interaction Details

- Heartbeat controller passes client telemetry and connection status into `Monitoring.heartbeat/2`.
- `Monitoring.heartbeat/2` updates device `last_seen_at`, persists telemetry, evaluates rules, and returns queued commands to the client.
- Offline checking uses `Settings.get_offline_window/0` and runs periodically through `OfflineChecker`.
- Offline timing is runtime-configured through settings instead of hard-coded in
  the module docs. See [Data Flow](../data-flow.md) for the heartbeat and
  offline-check sequence.

Traceable references:

- `packages/server/lib/nixstasis/monitoring.ex:15-148`
- `packages/server/lib/nixstasis/monitoring/offline_checker.ex:1-32`
- `packages/server/lib/nixstasis_web/controllers/heartbeat_controller.ex:7-27`
