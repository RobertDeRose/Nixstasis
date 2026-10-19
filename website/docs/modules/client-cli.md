# Client CLI

The `nixstasis` executable that runs on each managed device: a Cobra command tree that registers the device, runs the
polling loop, and manages Stary scripts. Installing it is covered in
[Client Installation](../operations/client-installation.md).

## Owns

- The command tree under `packages/client/cmd/nixstasis/`, rooted in `main.go`.
- Configuration loading through Viper (`internal/config`): `config.yaml` from `/etc/nixstasis`, then
  `$HOME/.config/nixstasis`, then the working directory, or the file named by `NIXSTASIS_CONFIG_FILE`, overridden by
  `NIXSTASIS_*` environment variables.
- A Go `runtime/trace` flight recorder; when a command fails and `NIXSTASIS_WRITE_TRACE_ON_ERROR=true`, it writes the
  trace under the system temp directory in `nixstasis/`.

## Entry points

| Command                           | Purpose                                                                                                                                           |
|-----------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| `nixstasis register`              | Detects the device identity and registers it with the server (`register.go`).                                                                     |
| `nixstasis poll`                  | Runs the heartbeat loop: sends telemetry, runs server commands, reports results, and starts or stops FRP tunnels (`poll.go`).                     |
| `nixstasis script install <path>` | Installs a Stary script.                                                                                                                          |
| `nixstasis script list`           | Lists installed scripts.                                                                                                                          |
| `nixstasis script remove <name>`  | Removes an installed script.                                                                                                                      |
| `nixstasis script test <path>`    | Runs a script and prints its YAML output.                                                                                                         |
| `nixstasis script repl`           | Opens an interactive Starlark REPL with the Stary builtins.                                                                                       |
| `nixstasis frp-session`           | Hidden. Runs one FRP tunnel session with a timeout; started by the transient systemd unit ([Client FRP Manager](client-frp-manager.md)).          |
| `nixstasis ssh-authorized-keys`   | Hidden. The `sshd` `AuthorizedKeysCommand` helper that prints a key only while it is authorized ([Runtime Boundaries](../runtime-boundaries.md)). |

## Boundaries

- The commands are thin: identity, transport, scripts, commands, FRP, telemetry, inventory, command policy, and SSH
  authorization live in the `internal/` packages described on the other Client pages.
- `register` and `poll` talk to the server only through [Client Transport](client-transport.md).
