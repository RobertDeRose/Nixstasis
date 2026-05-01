# Feature Specification: Nixstasis Packaging and Deployment Migration

**Feature Branch**: `013-nixstasis-packaging-migration`
**Created**: 2026-04-29
**Status**: Draft
**Input**: User description: "based on @package.md"

## Clarifications

### Session 2026-04-29

- Q: Must the supported deployment include a required public ingress/authentication layer as part of the standard stack? → A: Yes, the supported deployment must include a required public ingress/authentication layer as part of the standard stack.
- Q: Should this feature support both the bundled default database and an externally managed database? → A: Yes, this feature must support both the bundled default database and an externally managed database.
- Q: May legacy Nixstasis naming remain anywhere in scope for this feature? → A: No, legacy Nixstasis naming may not remain anywhere in scope for this feature.
- Q: Must all externally sourced runtime artifacts in scope be pinned and reproducible? → A: Yes, all externally sourced runtime artifacts in scope must be pinned and reproducible.
- Q: Must the runtime contract fully define all operator-supplied settings needed for a supported deployment? → A: Yes, the runtime contract must fully define all operator-supplied settings needed for a supported deployment.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy the server with one documented path (Priority: P1)

As a platform operator, I want one supported server deployment path for the product so I can install, configure, and run the platform consistently without relying on legacy package-specific server setup.

**Why this priority**: The migration is primarily driven by the need to replace the old server delivery model with a simpler, supported operational path.

**Independent Test**: Can be fully tested by following the documented server deployment instructions in a clean environment and confirming the full server stack starts with the required services, configuration inputs, and operator guidance.

**Acceptance Scenarios**:

1. **Given** a platform operator is preparing a new server deployment, **When** they follow the supported deployment instructions, **Then** they can start the full server stack from one source of truth with the required public ingress/authentication layer included and without using legacy server package workflows.
2. **Given** a running server deployment, **When** the operator reviews the deployment assets, **Then** the server application, ingress/authentication layer, tunnel service, and supported database configuration models are all represented as part of the same supported deployment flow.

---

### User Story 2 - Install the client as a native package with bundled tunnel support (Priority: P1)

As a device administrator, I want the client to remain installable as a native host package so I can deploy it on managed machines without requiring a separate tunnel package installation.

**Why this priority**: The client must preserve host-level integration while removing the operational burden of managing an additional runtime dependency.

**Independent Test**: Can be fully tested by installing the released client artifacts on a supported Linux host and verifying the user-facing command, bundled tunnel helper, configuration templates, and service integration are present and usable.

**Acceptance Scenarios**:

1. **Given** a device administrator installs the client package on a supported host, **When** installation completes, **Then** the client command, required configuration templates, service assets, and bundled tunnel helper are installed together.
2. **Given** the client is installed on a host without a separately installed tunnel package, **When** the client starts a tunnel session, **Then** it uses the bundled helper successfully.

---

### User Story 3 - Use the new Nixstasis product identity consistently (Priority: P2)

As an operator or administrator, I want the renamed product identity to appear consistently across releases, packages, runtime assets, code-visible identifiers, and documentation so I am not confused by mixed old and new naming.

**Why this priority**: The migration is also the planned cutover point for the public rename, and inconsistent naming would create support and adoption friction.

**Independent Test**: Can be fully tested by reviewing released assets, runtime-facing names, paths, and deployment documentation to confirm the new product name is used consistently and legacy naming is no longer presented as the default.

**Acceptance Scenarios**:

1. **Given** a user reads deployment or installation documentation after the migration, **When** they follow product references, **Then** the documentation uses Nixstasis as the primary product name.
2. **Given** a user inspects installed or deployed assets created or updated by this feature, **When** they view commands, service names, paths, package names, or documentation references, **Then** those assets use the Nixstasis naming convention with no remaining Nixstasis naming.

---

### User Story 4 - Operate against a clear runtime contract (Priority: P2)

As a platform operator, I want one documented runtime contract for ports, secrets, domains, and approval paths so I can configure the deployment correctly and avoid environment-specific guesswork.

**Why this priority**: Current mismatches in runtime expectations are a major source of deployment risk and must be resolved for the new delivery model to be reliable.

**Independent Test**: Can be fully tested by reviewing the runtime contract documentation and configuration templates, then confirming operators can supply the required values without conflicting names or ambiguous ownership.

**Acceptance Scenarios**:

1. **Given** an operator is preparing environment values for deployment, **When** they review the documented runtime contract, **Then** all operator-supplied settings required for a supported deployment, including ports, secrets, domain rules, and approval paths, are defined in one place.
2. **Given** multiple operators configure separate environments, **When** they use the same runtime contract documentation, **Then** they can produce compatible deployments without making different assumptions about core settings.

### Edge Cases

- An operator attempts to use deprecated server package instructions after the migration; the current documentation must clearly direct them to the supported server deployment path.
- A client host does not have any separately installed tunnel tooling; the packaged client must still be operational.
- A deployment uses a separately managed database instead of the default bundled database; the supported deployment flow must still accommodate that choice.
- An operator encounters legacy Nixstasis names in assets touched by this migration; those assets must be renamed to Nixstasis before the migration is considered complete.
- A required secret, domain rule, or approval path is missing or inconsistent; the deployment documentation and templates must make the gap obvious before production rollout.
- An operator attempts to complete deployment with only the documented runtime contract; no required operator-supplied setting should be discoverable only through source inspection or tribal knowledge.
- An externally sourced runtime artifact resolves to a different version between environments; the supported release process must prevent non-reproducible artifact selection.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a single supported server deployment model for this migration and remove abandoned legacy server package delivery from the supported release surface.
- **FR-002**: System MUST provide one deployment source of truth that defines the complete server stack, including the required public ingress/authentication layer, application service, database service, and tunnel service.
- **FR-003**: System MUST define and document one complete runtime contract for all operator-supplied settings required by the supported server deployment model.
- **FR-004**: System MUST allow the supported server deployment to run with either an included default database service or an externally managed database without requiring application behavior changes.
- **FR-005**: System MUST keep the client distributable as native host-installed release artifacts for supported Linux targets.
- **FR-006**: System MUST distribute the client with a bundled tunnel helper so client operation does not depend on a separately installed tunnel package.
- **FR-007**: System MUST install the bundled tunnel helper in a private product-owned location that is distinct from user-facing commands.
- **FR-008**: System MUST ensure the installed client uses the bundled tunnel helper by default during normal operation.
- **FR-009**: System MUST produce client release outputs that include archive and native package formats suitable for supported Linux environments.
- **FR-010**: System MUST apply the Nixstasis name consistently across newly created package names, binary names, service names, config paths, container names, image names, and deployment documentation generated by this migration.
- **FR-011**: System MUST remove Nixstasis naming from all assets created or updated within this feature scope and replace it with Nixstasis naming, including package metadata, runtime identifiers, documentation, and code namespaces where required to complete the rename.
- **FR-012**: System MUST provide documented server release operations that separate application startup from database migration execution.
- **FR-013**: System MUST update release and deployment guidance so users can identify `deploy/compose` and the image/client release workflows as the only source of truth for this migration.
- **FR-014**: System MUST define a controlled sourcing policy for all externally sourced runtime artifacts in scope so the deployed and packaged versions are pinned and reproducible across environments.

### Key Entities *(include if feature involves data)*

- **Server Deployment Stack**: The full set of server-side runtime services and configuration that operators use to run the product in a supported environment.
- **Client Release Artifact**: A host-installable client distribution that includes the user-facing command, bundled tunnel helper, configuration templates, and service assets.
- **Runtime Contract**: The complete documented set of operator-supplied settings needed to configure the product consistently, including ports, secrets, domain rules, and approval paths.
- **Naming Asset**: Any user-visible package, command, service, path, image, or document that must follow the Nixstasis naming convention after migration.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In validation testing, 100% of new server deployments for this release are performed through the documented supported deployment path rather than legacy server package instructions.
- **SC-002**: At least 95% of operators can complete an initial server deployment using the provided documentation and configuration templates without needing undocumented environment assumptions.
- **SC-003**: At least 95% of successful client installations on supported Linux targets complete without requiring a separately installed tunnel package.
- **SC-004**: 100% of release-facing product references within this feature scope use Nixstasis naming across client artifacts, server deployment assets, and updated documentation, with no remaining Nixstasis naming.
- **SC-005**: During release validation, 100% of operator-supplied settings required for a supported deployment can be identified from one documented source without conflicting names for the same setting.
- **SC-006**: During release validation, 100% of externally sourced runtime artifacts used by supported deployments and client packages resolve to documented pinned versions with identical results across environments.

## Assumptions

- Existing users of the product will accept the server deployment model change as long as one supported operational path is clearly documented.
- Existing host-level client behavior, such as configuration templates and service integration, remains required after the packaging migration.
- Abandoned legacy packaging artifacts are not required to remain in the repository during this migration and should be removed when they conflict with the new supported path.
- The migration covers packaging, deployment, runtime contract documentation, and naming alignment as one workstream rather than separate releases.
- Externally sourced runtime artifacts in scope can be identified and documented as part of release validation.
