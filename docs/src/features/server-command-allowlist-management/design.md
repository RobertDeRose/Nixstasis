# Server Command Allowlist Management

- Feature: `server-command-allowlist-management`
- Owner: server feature implementation

## Intent

Operators need a controlled server-side workflow to grant Stary `exec_cmd` capabilities to selected devices without weakening deny-by-default enforcement. The feature adds authoritative command policy authoring, grouping, assignment, and client delivery so script deployment permissions are explicit, auditable, and revocable.

## Requirements

- Allow operators to create and maintain command allowlist entries with:
  - command name (stable identifier)
  - absolute executable path
  - optional metadata/description
- Group allowlist entries into reusable collections (categories).
- Enforce validation rules for entries:
  - command name must be present and normalized
  - path must be absolute
  - reject shell fragments, empty values, duplicates in conflicting namespaces
- Assign allowlist entries or categories to selected devices.
- Show the resolved effective policy for each target device before assignment.
- Deliver policy to clients via a reliable authenticated path with idempotent behavior.
- Persist policy versioning and assignment state for audit and rollback.
- Respect device authorization boundaries for visibility and mutation.

## Constraints

- `exec_cmd` remains deny-by-default when no allowlist applies.
- Server cannot authorize shell strings; only explicit command names and absolute paths are in scope.
- Additive composition must surface conflicts (same command name -> different path).
- Policy assignment and usage are admin/operator-level capabilities.
- No cross-feature UI changes to script testing/deployment behavior beyond required integration.

## Non-goals

- Interactive shell proxying or general interactive command execution.
- Argument-level sandboxing/validation in the first increment unless already present in client runtime.
- Automatic inference of required commands by scanning script bodies.
- Replacing existing client-side enforcement model; policy application must remain bounded by client checks.

## Security and failure boundaries

- Server-side allowlist records must be auditable and enforce explicit actor identity/time.
- Device-scoped authorization prevents operators from modifying policies for unauthorized devices.
- Offline and duplicate assignment scenarios must not break existing command semantics (idempotent delivery semantics required).
- Delivery failures should be visible and retriable.

## Data model

- Command Allowlist
  - name
  - description
  - absolute command path
  - version
  - actor/timestamps
- Category
  - name
  - description
  - member allowlist refs
  - no nested category membership in first increment (direct members only)
- Device Policy Assignment
  - device_id
  - assigned allowlist/category refs
  - resolved policy snapshot
  - status (pending/queued/acknowledged/failed)
  - version marker
- Policy Delivery Result
  - assignment id
  - command ref
  - client result (delivered/acknowledged/failed)
  - result payload/timestamp

## Client/runtime contract

- First transport: extend the authenticated device command pipeline (`client_command` route/handler) to carry an `apply_command_policy` command carrying versioned allowlist payload.
- Client must parse and persist policy, then install it into runtime config used by Stary execution path.
- Policy delivery must be safe against out-of-order or repeated deliveries (idempotency keyed by policy version + assignment id).
- Clients that do not support policy updates should fail fast with explicit unsupported-command status for visibility.
- If command transport is unavailable, a heartbeat extension fallback may be considered only as a documented contingency for this increment.

## Suggested UX

- New admin screen for allowlist entries (CRUD).
- New admin screen for categories with conflict-aware effective-policy preview.
- Device policy assignment screen with per-device effective policy preview.
- Assignment detail/status screen with delivery result, retry, and revoke actions.
- Clear statuses for pending/queued/acknowledged/failed assignment states.

## Risks

- Client runtime drift between deliver methods and installed policy format.
- Permission overreach if device scoping leaks into policy assignment UI.
- Conflict ambiguity causing silent shadowing if composition rules are unclear.
- Deliverability regressions to offline or legacy clients.

## Validation and close-out

- Server tests for auth scope, policy conflict handling, assignment, and delivery idempotency.
- Client tests for policy ingestion and execution rejection/allowance behavior.
- End-to-end test for add/assign/update/revoke of policy and resulting `exec_cmd` behavior.
- Documentation reconciliation in close-out via `T999`.

## User-facing docs sections to update during implementation

- Operations: document assignment workflow, conflict handling, troubleshooting for stale/failed policies.
- Architecture: document server-to-client policy-delivery contract and precedence model.
- Development: document Ash resources/domain APIs and migration/testing notes for this feature.
- Reference: document command payload schema and allowlist field semantics.

## Dependencies

- `packages/server/lib/nixstasis_web/permissions.ex` and device permission plumbing.
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex` or equivalent command dispatch path.
- `packages/server/lib/nixstasis/devices.*`
- Stary runtime execution path in `packages/client` for policy consumption.
- `docs/src/features/server-stary-script-workbench/design.md` (integration point for `exec_cmd` behavior)
- `docs/src/planned-features.md` (status tracking)
