# Self-Extracting Installer

## Feature Name

`self-extracting-installer`

## Goal

Produce a single `.run` self-extracting archive per supported architecture as
part of the client release pipeline. The archive bundles the client binary,
arch-matched `frpc`, configuration templates, systemd units, and an artifact
manifest so that operators on systemd Linux distros without `dpkg` or `rpm` can
install Nixstasis with one command and no manual file placement.

## Source Of Intent

- `docs/src/planned-features.md`, feature `self-extracting-installer`
- Prior review findings M6 and Q3 from `nistasis.issues_resolved.md`

## Users

- Operators running systemd Linux distros without native deb/rpm support.
- CI pipelines that need a single download artifact for fleet provisioning.
- Developers validating the install experience without building from source.

## Requirements

1. Produce a `.run` self-extracting archive for each release architecture
   (`linux/amd64`, `linux/arm64`).
2. Each archive contains a flat staging directory with:

- `nixstasis` binary (copied from GoReleaser `dist/` build output)
- `frpc` binary (arch-matched, from `build/root-dir/usr/libexec/nixstasis/`)
- `frpc.toml` (from `build/root-dir/etc/nixstasis/`)
- `config.example.yaml` (from `build/root-dir/usr/share/nixstasis/`)
- `nixstasis-poll.service` (from `build/root-dir/lib/systemd/system/`)
- `nixstasis-poll.path` (from `build/root-dir/lib/systemd/system/`)
- `nixstasis-registration.service` (from `build/root-dir/lib/systemd/system/`)
- `install.sh` (FHS placement script)
- `artifacts.json` (manifest)

3. `install.sh` maps flat archive files to their FHS paths:

- `nixstasis` -> `/usr/bin/nixstasis`
- `frpc` -> `/usr/libexec/nixstasis/frpc`
- `frpc.toml` -> `/etc/nixstasis/frpc.toml` (only if not already present)
- `config.example.yaml` -> `/usr/share/nixstasis/config.example.yaml`
- Seeds `/etc/nixstasis/config.yaml` from `config.example.yaml` if not already
  present (matching nfpm postinstall behavior)
- `nixstasis-poll.service` -> `/lib/systemd/system/nixstasis-poll.service`
- `nixstasis-poll.path` -> `/lib/systemd/system/nixstasis-poll.path`
- `nixstasis-registration.service` -> `/lib/systemd/system/nixstasis-registration.service`

4. `install.sh` must be idempotent and safe for upgrades:

- Overwrite binaries and systemd units unconditionally.
- Preserve existing `/etc/nixstasis/frpc.toml` and
  `/etc/nixstasis/config.yaml` unless `--force-config` is passed.
- Print installed file paths and versions to stdout.

5. `artifacts.json` contains:

- `version`: release version string (sourced from GoReleaser `dist/metadata.json`)
- `arch`: target architecture
- `build_date`: ISO 8601 timestamp
- `files`: array of `{path, sha256, mode}` entries for every bundled file
  (paths are flat archive-relative names, not FHS destinations)

1. The release workflow produces `.run` archives into `dist/` after
   `verify_artifacts.sh` passes, and uploads them alongside existing release
   artifacts.
2. `verify_artifacts.sh` is extended to validate `.run` archive contents and
   manifest integrity.
3. `frpc` is consumed from `build/root-dir/usr/libexec/nixstasis/frpc_<arch>`
   (already staged by `fetch_frpc.sh` before GoReleaser runs), not downloaded
   separately.

## Constraints

- Do not embed `frpc` in the Go client binary.
- `FRPS_SERVER_ADDR` remains a runtime env var, not baked into the archive.
- Systemd units must retain `PrivateTmp=true`.
- `build/root-dir` stays as the GoReleaser staging source for file templates.
- `packages/frp` remains the shared source of truth for FRP version and
  checksums.
- The self-extracting archive is an additional release artifact; it does not
  replace `.deb`, `.rpm`, or `.tar.gz` outputs.
- `makeself` is the archive tool. It is available in Ubuntu 24.04 via
  `apt-get install makeself` and produces POSIX-compatible `.run` files.

## Non-Goals

- Replacing `.deb` or `.rpm` packaging for distros that support them.
- Interactive TUI installer or configuration wizard.
- Automatic `systemctl enable` or `systemctl start` on install.
- Uninstall support (can be added later).
- macOS or Windows support.
- Signing the `.run` archive (can be added later with GPG).

## Design

### Archive Assembly

A new script `packages/client/scripts/release/build_installer.sh` assembles
the `.run` archive:

1. Accept `DIST_DIR` (GoReleaser dist directory, default `dist`) and `ARCH`
   (`amd64` or `arm64`) as inputs.
2. Create a temporary staging directory.
3. Copy the compiled `nixstasis` binary from the GoReleaser build output in
   `dist/nixstasis_linux_<arch>/nixstasis`.
4. Copy `frpc` from `build/root-dir/usr/libexec/nixstasis/frpc_<arch>` and
   rename to `frpc`.
5. Copy config files from `build/root-dir/`:
   - `etc/nixstasis/frpc.toml` -> `frpc.toml`
   - `usr/share/nixstasis/config.example.yaml` -> `config.example.yaml`
6. Copy systemd units from `build/root-dir/lib/systemd/system/`:
   - `nixstasis-poll.service`
   - `nixstasis-poll.path`
   - `nixstasis-registration.service`
7. Copy `install.sh` from `scripts/release/install.sh`.
8. Read version from `dist/metadata.json` (GoReleaser output).
9. Generate `artifacts.json` by computing sha256 and recording mode for each
   file in staging.
10. Run `makeself --nox11 <staging> <output> <label>` to produce
    `nixstasis-<version>-linux-<arch>.run` into `dist/`.

### Install Script

`packages/client/scripts/release/install.sh` is a POSIX shell script that:

1. Checks for root privileges (`id -u` equals 0; avoids `$EUID` which is
   bash-only).
2. Requires a running systemd host.
3. Creates target directories if they do not exist.
4. Installs binaries and systemd units with correct permissions.
5. Conditionally installs config files:

- Always install `/usr/share/nixstasis/frpc.toml` from the archive so client
  upgrades can update the FRP template.
- Seed `/etc/nixstasis/config.yaml` from `config.example.yaml` if it does not
  exist (unless `--force-config`, which overwrites both).

6. Prints a summary of installed files and a reminder to configure
   `/etc/nixstasis/config.yaml` and run `systemctl enable`.

### Manifest Format

```json
{
  "version": "0.1.0",
  "arch": "amd64",
  "build_date": "2026-05-13T12:00:00Z",
  "files": [
    {"path": "nixstasis", "sha256": "abc123...", "mode": "0755"},
    {"path": "frpc", "sha256": "def456...", "mode": "0755"},
    {"path": "frpc.toml", "sha256": "...", "mode": "0644"},
    {"path": "config.example.yaml", "sha256": "...", "mode": "0644"},
    {"path": "nixstasis-poll.service", "sha256": "...", "mode": "0644"},
    {"path": "nixstasis-poll.path", "sha256": "...", "mode": "0644"},
    {"path": "nixstasis-registration.service", "sha256": "...", "mode": "0644"},
    {"path": "install.sh", "sha256": "...", "mode": "0755"}
  ]
}
```

### CI Integration

In `release_client.yml`, after `verify_artifacts.sh`:

1. `apt-get install -y makeself`
2. Run `build_installer.sh` for `amd64` and `arm64`.
3. `.run` files are written to `dist/`.
4. For snapshot builds: `dist/` is already uploaded as `nixstasis-client-snapshot`.
5. For tag builds: GoReleaser handles release artifact upload; `.run` files need
   an additional `gh release upload` step or `actions/upload-artifact` attachment.

### Verification Extension

`verify_artifacts.sh` gains a new section that:

1. Finds all `.run` files in `$DIST_DIR`.
2. Extracts each to a temp directory with `--noexec --target <dir>`.
3. Validates `artifacts.json` exists and is valid JSON (using `jq` or
   `python3 -m json.tool`).
4. Validates every file listed in `artifacts.json` exists and its sha256
   matches.
5. Validates the archive contains `install.sh`, `nixstasis`, and `frpc`.
6. Requires at least one `.run` file only when `VERIFY_INSTALLERS=true`, so the
   existing pre-installer artifact verification step can still validate tar,
   deb, and rpm outputs before installers are built.

## Risks And Tradeoffs

- `makeself` is a CI runtime dependency; pinning its version prevents
  surprising format changes. This feature uses the Ubuntu 24.04 package first;
  explicit version pinning can be added later if release reproducibility needs
  it.
- Self-extracting archives are less auditable than plain tarballs; operators
  who prefer inspection can use `--noexec --target <dir>` to extract without
  running.
- `install.sh` config preservation adds conditional logic that must be tested
  for both fresh install and upgrade paths.
- No uninstall script means operators must manually remove files or wait for
  a future feature.
- `EUID` is bash-only; `install.sh` uses `id -u` for POSIX compatibility.

## Dependencies

- `packages/frp/bin/download_frp.sh` (shared FRP acquisition, already used)
- `packages/client/scripts/fetch_frpc.sh` (stages frpc into build/root-dir)
- `.github/workflows/release_client.yml` (release pipeline)
- `packages/client/scripts/release/verify_artifacts.sh` (artifact validation)
- `packages/client/build/root-dir/` (FHS layout source)
- `prod.env` (FRP version pins)
- `packages/client/.goreleaser.yaml` (archive structure reference)

## Affected Docs

- `packages/client/README.md` (document `.run` installer usage)
- `docs/src/planned-features.md` (keep feature status and delivered behavior
  reconciled as the feature moves from `in-spec` to `in-progress` and
  `completed`)

## Suggested Validation

- CI step that builds `.run` from snapshot artifacts, extracts, and verifies
  manifest integrity.
- Extraction test on Ubuntu 24.04 (CI runner) confirming all files land.
- Manual smoke test on a systemd distro without `dpkg`/`rpm` to confirm FHS
  placement.
- Upgrade test: install v1, then install v2, confirm binaries are replaced but
  config is preserved.
- Config seeding test: fresh install seeds `config.yaml` from example; upgrade
  preserves existing `config.yaml`.
