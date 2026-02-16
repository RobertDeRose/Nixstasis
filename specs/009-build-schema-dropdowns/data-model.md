# Data Model: Schema-Driven Builder Dropdowns

**Date**: 2026-02-14

## Entities

### BuilderSchemaSelection
- **Fields**:
  - `builder_type` (`alert` | `report`)
  - `schema_id` (string)
  - `schema_version` (string)
  - `selected_at` (utc datetime)
- **Notes**: Represents the active schema context for one builder flow. Alert and report selections are independent.

### SchemaDefinitionRef
- **Fields**:
  - `schema_id` (string, required)
  - `schema_version` (string, required)
  - `product_name` (string, optional)
  - `readable` (boolean)
- **Notes**: Identifies the schema source used to derive dropdown options and validation behavior.

### SchemaOption
- **Fields**:
  - `key` (string, canonical field key/path)
  - `label` (string, user-facing option text)
  - `value_type` (string, optional descriptive type)
  - `order_index` (integer)
  - `selectable` (boolean)
- **Notes**: Canonical dropdown entry derived from schema metadata. Ordering and naming must be consistent across builders for same schema input.

### BuilderFieldSelection
- **Fields**:
  - `builder_type` (`alert` | `report`)
  - `selection_slot_id` (string)
  - `selected_key` (string)
  - `valid_for_schema` (boolean)
  - `last_validated_at` (utc datetime)
- **Notes**: Tracks each selected dropdown value and whether it remains valid after schema or authorization changes.

### BuilderValidationIssue
- **Fields**:
  - `issue_code` (`invalid_schema_field` | `schema_unavailable` | `schema_access_lost`)
  - `message` (string)
  - `builder_type` (`alert` | `report`)
  - `selection_slot_id` (string, optional)
  - `blocking` (boolean)
- **Notes**: User-visible inline feedback emitted when selections become invalid or schema access/readability problems occur.

## Relationships

- One **BuilderSchemaSelection** references one **SchemaDefinitionRef**.
- One **SchemaDefinitionRef** produces many **SchemaOption** entries.
- One **BuilderSchemaSelection** has many **BuilderFieldSelection** entries.
- One **BuilderFieldSelection** may emit many **BuilderValidationIssue** records over time.

## Validation Rules

- `builder_type` must be either `alert` or `report`.
- (`schema_id`, `schema_version`) is required for loading options.
- `SchemaOption.key` must be unique within the same (`schema_id`, `schema_version`) set.
- `BuilderFieldSelection.selected_key` must exist in active `SchemaOption.key` set to be valid.
- Save actions are blocked when any blocking `BuilderValidationIssue` exists.

## State Transitions

### BuilderFieldSelection.valid_for_schema
- `true -> false` when schema changes and selected key is absent in new option set.
- `true -> false` when schema access is lost or schema becomes unreadable.
- `false -> true` when user reselects a valid key under active schema context.

### BuilderValidationIssue lifecycle
- `created` when mismatch/unavailable/access-loss is detected.
- `resolved` when schema/options recover and user selections satisfy active validation.
