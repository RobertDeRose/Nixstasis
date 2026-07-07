# Server Command Allowlist Management

- Feature: `server-command-allowlist-management`
- Owner: server feature implementation

## Intent

Operators need a controlled server-side workflow to grant Stary `exec_cmd` capabilities to selected devices without weakening deny-by-default enforcement. The feature adds authoritative command policy authoring, grouping, assignment, and client delivery so script deployment permissions are explicit, auditable, and revocable.

## Requirements

- Treat one command entry as the atomic record: one stable command name mapped to one absolute executable path.
- Allow operators to create and maintain command entries with:
  - command name (stable identifier)
  - absolute executable path
  - optional metadata/description
- Group command entries into reusable collections (categories).
- Keep first-version category composition direct-only: categories may include command entries, not other categories.
- Enforce validation rules for entries:
  - command name must be present, normalized, case-insensitively unique, and limited to lowercase letters, digits, `_`, `-`, and `.`
  - path must be absolute and syntactically valid without whitespace or shell metacharacters
  - reject shell fragments, empty values, and duplicate command names with different paths in the same resolved policy
  - allow duplicate absolute paths under different command names
- Assign command entries or categories to selected approved devices.
- Show the resolved effective policy for each target device before assignment and require confirmation before enqueueing delivery.
- Deliver policy to clients through the existing heartbeat command pipeline using an `apply_command_policy` command.
- Persist policy versioning and assignment state for audit and rollback.
- Respect device authorization boundaries for visibility and mutation.

## Constraints

- `exec_cmd` remains deny-by-default when no allowlist applies.
- Server cannot authorize shell strings; only explicit command names and absolute paths are in scope.
- Additive composition must surface conflicts (same command name -> different path).
- Policy assignment and usage are admin/operator-level capabilities, narrowed by device-scope claims.
- Viewers may see policy status for visible devices, but full command paths and global inventory are operator/admin-only in v1.
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
- The persisted assignment snapshot is the source of truth for what the server intended to deliver; the client acknowledgement is evidence of durable application, not authorization by itself.
- Failed assignments keep the last acknowledged client policy active; they do not implicitly deny all or partially apply non-conflicting commands.
- Removing an assignment must enqueue a higher-revision replacement snapshot recalculated from remaining assignments; empty policy means deny all when nothing remains.

## Data model

- Command Entry
  - name
  - description
  - absolute command path
  - immutable version/revision per security-relevant save
  - archived/read-only state instead of hard-delete when referenced
  - actor/timestamps
- Category
  - name
  - description
  - member command entry refs pinned to versions
  - immutable version/revision per membership change
  - archived/read-only state instead of hard-delete when referenced
  - no nested category membership in first increment (direct members only)
- Device Policy Assignment
  - device_id for an approved device
  - assigned command entry/category refs pinned to versions
  - resolved policy snapshot with immutable full paths and source provenance
  - status (`pending`, `queued`, `acknowledged`, `failed`, `revoked`)
  - optional drift warning/health flag separate from lifecycle status
  - monotonically increasing per-device policy revision
  - version/assignment id for audit/debug
- Policy Delivery Result
  - assignment id
  - command ref
  - client result (delivered/acknowledged/failed)
  - result payload/timestamp
  - failure reason when unsupported, stale, conflicting, or persistence fails

## Client/runtime contract

- First transport: use the authenticated heartbeat command pipeline (`PollResponse.Commands`) to carry an `apply_command_policy` command with a versioned allowlist payload.
- Payload v1 content type is `application/vnd.nixstasis.command-policy+json;version=1`.
- Payload v1 shape is `{ "assignment_id": "uuid", "version": "human/audit version", "revision": 123, "commands": { "name": "/absolute/path" } }`.
- The server must queue the command with the same pending-command/result flow documented in `docs/src/data-flow.md`; no new `/api/v1` client endpoint is needed for this increment.
- Client must parse and durably persist policy outside the script directory, then install it into runtime config used by Stary execution path before acknowledging success.
- Server-delivered policy overrides local configured allowlists when present; local config is fallback only when no server policy has been delivered. An empty delivered policy means deny all.
- Policy delivery must be safe against out-of-order or repeated deliveries: reject lower revisions, accept same revision with identical commands as idempotent, and fail same revision with different commands as a conflict while keeping the current policy.
- Clients that do not support policy updates already report unsupported command types through command results; surface that as an operator-visible assignment failure.
- Heartbeat may include a minimal current-policy revision/status echo if cheap; command results remain sufficient for v1 if not.
- If heartbeat echo exists, drift is reported as a warning/health flag only; the server must not auto-redeploy without operator action.
- Heartbeat response extensions for delivering policy are out of scope unless the command pipeline cannot carry the payload after implementation evidence.

## Suggested UX

- New admin screen for command entries (CRUD/archive/duplicate; archived records are read-only).
- New admin screen for categories with conflict-aware effective-policy preview.
- Device policy assignment screen with per-device effective policy preview and simple confirmation.
- Assignment detail/status screen with delivery result, retry, revoke, rollback-as-new-revision, raw payload debug for operators/admins, and optional drift warning.
- Clear statuses for `pending`, `queued`, `acknowledged`, `failed`, and `revoked` assignment states.

## Future considerations

- Script workbench/test orchestration should later account for effective command policy when a script uses `exec_cmd`; this feature does not block tests on policy assignment in v1.
- Typed confirmation, device-group assignment, argument allowlisting, nested categories, and heartbeat drift remediation are deferred until concrete need appears.

## Risks

- Client runtime drift between deliver methods and installed policy format.
- Permission overreach if device scoping leaks into policy assignment UI.
- Conflict ambiguity causing silent shadowing if composition rules are unclear.
- Deliverability regressions to offline or legacy clients.

## Validation and close-out

- Server tests for auth scope, policy conflict handling, assignment, command queueing, result acknowledgement, and revoke/narrow behavior.
- Client tests for policy ingestion, persistence, idempotency, and execution rejection/allowance behavior.
- End-to-end test for add/assign/update/revoke of policy and resulting `exec_cmd` behavior.
- Documentation reconciliation in close-out via `T999`, including `docs/src/planned-features.md` status if the implementation completes.

## User-facing docs sections to update during implementation

- Operations: update `docs/src/operations/index.md` or a new operations page with assignment workflow, conflict handling, rollback/revoke, and stale/failed policy troubleshooting.
- Architecture: update `docs/src/client-server-interface.md`, `docs/src/data-flow.md`, `docs/src/modules/client-command-handler.md`, `docs/src/modules/client-starlark-runtime.md`, and `docs/src/modules/server-devices.md` with the policy-delivery contract and deny-by-default enforcement model.
- Development: update `docs/src/development.md` and relevant module docs with Ash resources/domain APIs, migrations, and test commands for this feature.
- Reference: update `docs/src/reference/contracts.md` with `apply_command_policy` payload schema and allowlist field semantics.

## Dependencies

- `packages/server/lib/nixstasis_web/permissions.ex` and device permission plumbing.
- `packages/server/lib/nixstasis_web/controllers/device_command_controller.ex` or equivalent command dispatch path.
- `packages/server/lib/nixstasis/devices.*`
- Stary runtime execution path in `packages/client` for policy consumption.
- `docs/src/features/server-stary-script-workbench/design.md` (integration point for `exec_cmd` behavior)
- `docs/src/planned-features.md` (status tracking)
