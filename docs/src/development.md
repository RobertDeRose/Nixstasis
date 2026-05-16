# Development

Development documentation covers workflows that exist to build, validate, or
exercise Nixstasis locally. These docs are not production operating procedures.

## Local Stack

- [Compose Dev Harness](features/compose-dev-harness/design.md) describes the
  local deployment-shaped stack for validating Caddy TLS approval, FRP, managed
  device simulation, and browser-launched SSH terminal flows.
- Production deployment belongs in [Deployment Compose](modules/deployment-compose.md);
  this section is for local validation and developer feedback loops.
- Default laptop mode uses local hostnames and local/internal Caddy certificates
  so developers can exercise application behavior without public DNS or public
  certificate issuance.
- Optional public-fidelity validation can use DuckDNS or an operator-owned domain
  when public ACME behavior needs to be tested.

## Validation Boundaries

- Local development should preserve the production-shaped boundary where browser
  traffic reaches Phoenix through Caddy.
- Terminal testing should exercise LiveView, Phoenix Channels, server-side SSH,
  FRP TCP mux, and the managed client path instead of direct shell shortcuts.
- Development-only certificates, local keys, generated Compose overrides, and
  runtime state stay out of source control.

## Open Questions

- [Operational Unknowns](unknowns.md) tracks open implementation and operations
  questions that should be resolved before promoting a workflow to production
  guidance.
