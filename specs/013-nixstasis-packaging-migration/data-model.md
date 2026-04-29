# Data Model: Nixstasis Packaging and Deployment Migration

**Date**: 2026-04-29

## Entities

### RuntimeContract
- **Fields**:
  - `application_host` (string; canonical public host for the Phoenix application)
  - `base_domain` (string; suffix used for reserved and device-specific hosts)
  - `database_url` (string; operator-supplied database connection string)
  - `secret_key_base` (string; required application secret)
  - `app_port` (integer; canonical internal Phoenix port behind Caddy)
  - `auth_client_id` (string)
  - `auth_client_secret` (secret string)
  - `auth_tenant_id` (string)
  - `auth_jwt_key` (secret string)
  - `frps_bind_port` (integer)
  - `frps_http_port` (integer)
  - `frps_dashboard_port` (integer)
  - `frps_tcpmux_port` (integer)
  - `tls_approval_path` (string; canonical approval endpoint)
- **Notes**: Represents the full set of operator-supplied settings required for a supported deployment.

### ComposeDeploymentStack
- **Fields**:
  - `services` (list of `ComposeService`)
  - `default_database_mode` (`bundled`)
  - `supported_database_modes` (`bundled` | `external`)
  - `public_edge_required` (boolean)
  - `migration_execution_mode` (`explicit`)
  - `source_of_truth_path` (string; `deploy/compose`)
- **Notes**: Captures the operator-facing deployment model that supersedes legacy server package delivery.

### ComposeService
- **Fields**:
  - `name` (`postgres` | `nixstasis` | `frps` | `caddy`)
  - `image_or_build_source` (string)
  - `published_ports` (list of integers or port mappings)
  - `depends_on` (list of service names)
  - `runtime_inputs` (list of `RuntimeContract` field references)
  - `visibility` (`public` | `internal`)
- **Notes**: Defines service-level responsibilities inside the supported Compose stack.

### ExternalRuntimeArtifact
- **Fields**:
  - `name` (string; e.g. `frps-image`, `frpc-binary`, base image identifier)
  - `source_type` (`image` | `binary`)
  - `source_location` (string)
  - `pin_type` (`digest` | `checksum` | `version+checksum`)
  - `pin_value` (string)
  - `provenance` (`internal-mirror` | `upstream`)
  - `consumers` (list of package or deployment assets)
- **Notes**: Tracks the reproducible sourcing policy required for all externally sourced runtime assets in scope.

### ClientReleaseArtifact
- **Fields**:
  - `binary_name` (`nixstasis`)
  - `formats` (`archive` | `deb` | `rpm`)
  - `supported_targets` (list of Linux OS/arch tuples)
  - `bundled_frpc_path` (`/usr/libexec/nixstasis/frpc`)
  - `config_root` (`/etc/nixstasis/`)
  - `service_assets` (list of installed service/template files)
- **Notes**: Represents the output of the GoReleaser-native client release flow.

### NamingAsset
- **Fields**:
  - `asset_path` (string)
  - `asset_type` (`binary` | `package` | `service` | `config-path` | `container` | `image` | `documentation`)
  - `required_name` (`nixstasis`-based identifier)
  - `legacy_name_found` (boolean)
  - `migration_status` (`pending` | `renamed`)
- **Notes**: Used to reason about rename completeness across all touched assets.

## Relationships

- One **ComposeDeploymentStack** has many **ComposeService** entries.
- One **ComposeDeploymentStack** depends on one **RuntimeContract**.
- One **ComposeService** may consume many **ExternalRuntimeArtifact** entries.
- One **ClientReleaseArtifact** consumes one bundled `frpc` **ExternalRuntimeArtifact** and many **NamingAsset** entries.
- One **NamingAsset** can belong to either the **ComposeDeploymentStack** or the **ClientReleaseArtifact** deliverable set.

## Validation Rules

- `RuntimeContract` must contain every operator-supplied setting required for a supported deployment; no required value may exist only in source code or tribal knowledge.
- `RuntimeContract.app_port` must resolve to the same internal Phoenix port used by both server runtime config and Caddy proxy config.
- `RuntimeContract.tls_approval_path` must match the path documented in deployment assets and exposed by the server.
- `ComposeDeploymentStack.public_edge_required` must remain `true` for supported deployments.
- `ComposeDeploymentStack.supported_database_modes` must include both `bundled` and `external`.
- Every **ExternalRuntimeArtifact** must have a documented pin and provenance record.
- Every **ClientReleaseArtifact** must install the bundled `frpc` at `/usr/libexec/nixstasis/frpc` and must not require a separately installed FRP package.
- Every **NamingAsset** touched by this feature must end in `migration_status = renamed` before release validation completes.

## State Transitions

### NamingAsset.migration_status
- `pending -> renamed` when the asset is updated from `Nixstasis` naming to `Nixstasis` naming.

### ComposeDeploymentStack.default_database_mode
- `bundled` remains the default for first-run deployments.
- `bundled -> external` when an operator supplies an external PostgreSQL connection via the runtime contract.

### ExternalRuntimeArtifact.provenance
- `internal-mirror` is preferred when a mirrored pinned artifact exists.
- `upstream` is allowed only when the artifact still has a documented immutable digest or checksum.
