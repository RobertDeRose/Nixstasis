# Client agent guide

The Go device agent: a Cobra CLI in `cmd/nixstasis` with its packages under `internal/`. Read
`website/docs/repository-structure.md` for the layout and `website/docs/modules/client-*.md` for module architecture.

## Commands

Run from `packages/client`; Go and the Go tools come from this directory's `mise.toml`.

- `mise run test`: unit tests with the race detector and coverage.
- `mise x -- go test -tags no_sshd_integration ./...`: what CI runs. The untagged real-sshd test needs a root-owned
  `AuthorizedKeysCommand`, so use this tag unless you can provide one.
- `mise run build`: build `bin/nixstasis`.
- `mise run check` and `mise run fix` from the repository root run gofumpt, goimports with
  `-local github.com/RobertDeRose/nixstasis/packages/client`, golangci-lint, and `go mod tidy`.
- `scripts/e2e/run`: E2E journeys against a running server; requires `NIXSTASIS_E2E_RUNNER_ID` and
  `NIXSTASIS_E2E_RUNNER_TOKEN`. See `README.md` for suites and journeys.

## Conventions

- The runtime and release targets are Linux only. Native service, SSH packaging, and release-artifact validation need a
  Linux host.
- Log through `internal/logging`, which wraps `log/slog`.
- Configuration loads through Viper in `internal/config`.
- Telemetry scripts are Starlark, run by `internal/script`.
- Use `scripts/mock_api` as the fake server API in tests.
- The version comes from the `-X main.version` linker flag at release; local builds report `dev`.
