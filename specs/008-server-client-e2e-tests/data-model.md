# Data Model: Server-Client End-to-End Tests

**Date**: 2026-02-10

## Entities

### JourneyDefinition
- **Fields**: id, name, description, tags, preconditions, steps, expected_outcomes, required_test_data, timeout_seconds
- **Notes**: Represents a single end-to-end journey that can be run independently.

### TestSuite
- **Fields**: id, name, description, journey_ids, selection_tags, created_at, updated_at
- **Notes**: A named collection of journeys used for full or targeted runs.

### TestRun
- **Fields**: id, suite_id, journey_ids, trigger_source (manual|ci), environment_label, client_version, server_version,
  status, started_at, finished_at, initiated_by, run_metadata
- **Notes**: Represents a single execution of a suite or subset.

### TestResult
- **Fields**: id, run_id, journey_id, status (passed|failed|skipped), failure_step, failure_reason, log_ref,
  started_at, finished_at, duration_ms
- **Notes**: Per-journey outcome details used for reporting.

### TestEnvironment
- **Fields**: id, label, base_url, reset_strategy, seed_version, readiness_checks
- **Notes**: Non-production environment where E2E runs execute.

## Relationships

- **TestSuite** has many **JourneyDefinition** entries.
- **TestRun** belongs to a **TestSuite** and has many **TestResult** entries.
- **TestResult** belongs to a **TestRun** and references a **JourneyDefinition**.
- **TestRun** references a **TestEnvironment** by label.

## Validation Rules

- JourneyDefinition.name is unique.
- TestSuite.journey_ids must reference existing JourneyDefinition entries.
- TestRun.journey_ids must be a subset of the suite's journey_ids.
- TestRun requires client_version and server_version with the same major version.
- TestRun requires environment_label that maps to a ready TestEnvironment.
- TestResult.status must be one of passed, failed, skipped.

## State Transitions

### TestRun.status
- queued -> running -> passed
- queued -> running -> failed
- queued -> running -> cancelled
- queued -> blocked (precondition failure)
