# Research: Devices Page and Device Modal Improvements

**Date**: 2026-02-20
**Spec**: `/Users/DeRoseR/workspace/checkpoint/sfero-nixstasis/specs/012-improve-devices-modal/spec.md`

## Decisions

### 1) Modal integration source of truth
- **Decision**: Reuse the device modal interaction model established in spec `005-enhance-device-list`, including terminal (`xterm.js` via channel) and PCP data tabs, without introducing a second modal variant.
- **Rationale**: A single modal implementation avoids UX drift and lowers maintenance cost while meeting the requirement to expose the existing modal from Devices page MAC links.
- **Alternatives considered**: Rebuild a new modal for this page; expose a reduced-details modal only.

### 2) Column and label updates on devices list
- **Decision**: Add a `Product` column to device rows and relabel the primary identifier column from `Device Name` to `MAC Address` while preserving existing MAC normalization rules.
- **Rationale**: Aligns table semantics with the requested operator workflow and makes row identity consistent with current operations usage.
- **Alternatives considered**: Keep original `Device Name` label and add a secondary MAC field; hide product within modal only.

### 3) Multi-column click-to-filter behavior
- **Decision**: Clicking Product/Account Number/Status values will build an additive AND filter set keyed by column. First click creates filter state; subsequent clicks in different columns append constraints.
- **Rationale**: Matches the explicit user workflow and supports progressive narrowing without losing prior context.
- **Alternatives considered**: Replace-on-click behavior; OR-based additive model.

### 4) Filter removal semantics
- **Decision**: Support both per-filter removal and `Clear all`.
- **Rationale**: This resolves the open interaction ambiguity while preserving rapid experimentation: users can remove one condition without discarding the rest, and still reset instantly.
- **Alternatives considered**: `Clear all` only; per-filter only with no global reset.

### 5) Page-to-modal wiring contract
- **Decision**: MAC Address cell is the canonical modal entrypoint on the Devices table; opening/closing the modal must preserve list filter and scroll context.
- **Rationale**: Satisfies requested linkage and prevents workflow disruption when operators inspect multiple devices.
- **Alternatives considered**: Keep row click as trigger; open modal in separate route.

### 6) Performance and UX guardrails
- **Decision**: Keep list interactions server-driven with bounded query parameters and indexed filter columns (product, account number, status) and maintain existing modal latency targets from spec 005.
- **Rationale**: Preserves responsiveness under fleet-scale tables and adheres to constitution performance/UX principles.
- **Alternatives considered**: Client-only filtering over full list payload; no explicit bounds on filter interactions.
