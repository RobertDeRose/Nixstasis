# E2E API

The routes the end-to-end test harness uses to start runs, submit results, read logs, and cancel runs. Only the test
harness calls them, and only when E2E is enabled on the server. How the harness uses them is covered in
[Client E2E Harness](client-harness.md) and [Server E2E](server.md); each route's exact request and response format is
on the operation pages listed under this page in the sidebar, generated from
[`e2e-api.yaml`](../../reference/openapi/e2e-api.yaml).

## Routes

| Endpoint                                    | Handler                           | Purpose                |
|---------------------------------------------|-----------------------------------|------------------------|
| `GET /e2e/suites`                           | `E2ERunController.suites/2`       | List configured suites |
| `GET /e2e/runs`                             | `E2ERunController.index/2`        | List runs              |
| `POST /e2e/runs`                            | `E2ERunController.create/2`       | Create or reuse run    |
| `GET /e2e/runs/:id`                         | `E2ERunController.show/2`         | Fetch run              |
| `POST /e2e/runs/:id/cancel`                 | `E2ERunController.cancel/2`       | Cancel run             |
| `GET /e2e/runs/:id/results`                 | `E2ERunResultController.index/2`  | List results           |
| `POST /e2e/runs/:id/results`                | `E2ERunResultController.create/2` | Submit results         |
| `GET /e2e/runs/:id/results/:journey_id/log` | `E2ERunResultController.log/2`    | Fetch journey log      |

Every E2E route needs `X-E2E-Runner-ID` and `Authorization: Bearer <token>`. The runner identity has nothing to do
with operator roles, and a runner owns every run it creates. Asking for another runner's run, results, or logs gets
`404`, as if it did not exist. Creating a run also needs `X-E2E-Protocol-Version`; version `1` is the supported default.

## Examples

Run creation request:

```http
POST /e2e/runs
X-E2E-Runner-ID: ci-runner
Authorization: Bearer <runner-token>
X-E2E-Protocol-Version: 1
Content-Type: application/json
```

```json
{
  "suite_id": "full",
  "environment_label": "local",
  "trigger_source": "manual",
  "metadata": {"requested_by": "operator@example.invalid"}
}
```

Run creation response:

```json
{
  "data": {
    "id": "44444444-4444-4444-8444-444444444444",
    "suite_id": "full",
    "journey_ids": ["auth", "dashboard"],
    "environment_label": "local",
    "trigger_source": "manual",
    "protocol_version": "1",
    "status": "queued"
  }
}
```

To reuse a run rather than start a new one, send the same request with the `idempotency_key` of an existing run:

```json
{
  "suite_id": "full",
  "environment_label": "local",
  "trigger_source": "ci",
  "idempotency_key": "ci-2026-05-30T120000Z"
}
```

The response is the existing run, in the same format as a new one:

```json
{
  "data": {
    "id": "44444444-4444-4444-8444-444444444444",
    "suite_id": "full",
    "journey_ids": ["auth", "dashboard"],
    "environment_label": "local",
    "trigger_source": "ci",
    "protocol_version": "1",
    "status": "queued"
  }
}
```

Environment lock conflict response:

```json
{
  "error": {
    "code": "environment_locked",
    "message": "Environment 'local' already has an active E2E run."
  }
}
```

Protocol mismatch response:

```json
{
  "error": {
    "code": "protocol_mismatch",
    "message": "Unsupported protocol version '99'."
  }
}
```

Seed failure response:

```json
{
  "error": {
    "code": "seed_failed",
    "message": "Baseline test data is missing. Seed script not found for environment 'local'."
  }
}
```

Cancellation response:

```json
{
  "data": {
    "id": "44444444-4444-4444-8444-444444444444",
    "status": "cancelled"
  }
}
```

Result submission request:

```json
{
  "results": [
    {
      "journey_id": "auth",
      "status": "passed",
      "duration_ms": 1200,
      "log_ref": "runs/44444444-4444-4444-8444-444444444444/auth.jsonl"
    }
  ]
}
```

Result submission response:

```json
{
  "data": [
    {
      "journey_id": "auth",
      "status": "passed",
      "duration_ms": 1200,
      "log_ref": "runs/44444444-4444-4444-8444-444444444444/auth.jsonl"
    }
  ]
}
```

Journey log response:

```json
{
  "data": {
    "run_id": "44444444-4444-4444-8444-444444444444",
    "journey_id": "auth",
    "content": "{\"status\":\"ok\"}\n"
  }
}
```

Missing or pruned log response:

```json
{
  "error": {
    "code": "log_unavailable",
    "message": "Log is unavailable (possibly pruned or deleted)."
  }
}
```
