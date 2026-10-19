# Self-Extracting Installer

Client releases include a `.run` installer for each architecture, for systemd Linux hosts that don't use deb or rpm
packages. Each one carries the client, a matching `frpc`, configuration templates, systemd units, the installer
script, and a manifest with checksums. The original plan is in the [design record](design.md).

## What changed for users

Run the downloaded installer with `sh`. It installs into the standard Linux locations, and keeps your existing
`/etc/nixstasis/config.yaml` unless you ask it to replace it. You can also unpack it without running anything, to look
inside. Step-by-step instructions are in [Client Installation](../../operations/client-installation.md).

## How it fits in

The installer is built from the same GoReleaser output, and downloads FRP the same way. It is offered alongside the
deb, rpm, and tar packages, not instead of them, and installs the same systemd layout.

## Running it

Upgrading replaces the client's binaries, templates, and units, and keeps your configuration. The installer does not
enable services for you.

## Differences from the design

Release tooling was brought together under mise, with GoReleaser still building the artifacts.

## Not included

- Installers are not signed, and there is no uninstall command.
- The installer does not replace the native packages or start services automatically.
- It is for Linux only, not macOS or Windows.

## Tests

- `packages/client/build/bin/verify_artifacts.sh` with `VERIFY_INSTALLERS=true` unpacks each `.run` file without
  running it, and checks the required files, their permissions, and the manifest.
- `.github/workflows/release_client.yml` runs that check before uploading release artifacts.

## Related pages

- [Client Installation](../../operations/client-installation.md)
- `packages/client/README.md`
- [`packages/client/build/bin/verify_artifacts.sh`](../../../../packages/client/build/bin/verify_artifacts.sh)
- [`packages/client/build/makeself/entrypoint.sh`](../../../../packages/client/build/makeself/entrypoint.sh)
