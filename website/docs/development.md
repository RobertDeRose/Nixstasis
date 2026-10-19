# Development

This guide covers building, testing, and changing Nixstasis. Production procedures live in the
[Operations](operations/index.md) section.

Linux is the supported runtime, release, and packaging-validation platform. Running developer tools on another host
does not establish native support for that platform, and native client packaging checks must run on Linux.

## Guides

- [Developer Tooling](development/tooling.md): installing tools, the `mise` tasks, checks, hooks, and the documentation
  site.
- [Feature Lifecycle](development/feature-lifecycle.md): how features move from design to a delivered record.
- [Documentation Conventions](development/documentation-conventions.md): where pages go and how to write them.
- [Tooling Reference](development/tooling-reference.md): every check, task, and commit rule.
- E2E Testing: the [client harness](development/e2e/client-harness.md), the [server side](development/e2e/server.md),
  and published [results](development/e2e/results.md).
- [Local Stack](development/local-stack.md): running the full stack with device simulators, and the deployment
  contract checks.
- [Releasing](development/releasing.md): cutting a release from `dev` to `main`.
- [GitHub Pages Deployment](development/github-pages.md): enabling and running the documentation site deployment.

## Local stack

The local stack mirrors the production deployment so Caddy TLS approval, FRP, managed-device simulation, and
browser-launched SSH terminals can be exercised end to end; [Local Stack](development/local-stack.md) describes how to
run it.

- Laptop mode uses local hostnames and internal Caddy certificates, so no public DNS or certificate issuance is needed.
- Public-fidelity validation can use DuckDNS or an operator-owned domain when public ACME behavior must be tested.

## Standards

- User-facing features meet WCAG 2.1 AA: contrast ratios, visible keyboard focus, form labels, error announcements, and
  modal dialog behavior.
- Local development keeps the production boundary in which browser traffic reaches Phoenix through Caddy.
- Terminal testing exercises LiveView, Phoenix Channels, server-side SSH, FRP TCP muxing, and the managed client rather
  than direct shell shortcuts.
- Development certificates, local keys, generated Compose overrides, and runtime state stay out of source control.
