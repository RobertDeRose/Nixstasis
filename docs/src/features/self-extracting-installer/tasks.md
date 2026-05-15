# Tasks: Self-Extracting Installer

- [x] T000 Confirm feature scope against the reviewed spec before implementation.
- [x] T001 Create `packages/client/scripts/release/install.sh` with POSIX root check (`id -u`), FHS placement, config preservation, `config.yaml` seeding, and `--force-config` flag.
- [x] T002 Create `packages/client/scripts/release/build_installer.sh` that stages files from `build/root-dir/` and GoReleaser build output, generates `artifacts.json` from `dist/metadata.json`, and runs `makeself`.
- [x] T003 Extend `verify_artifacts.sh` to extract `.run` files with `--noexec --target <dir>`, validate `artifacts.json` schema and sha256 checksums, and confirm required files are present.
- [x] T004 Update `release_client.yml` to install `makeself`, run `build_installer.sh` for amd64 and arm64 after verify, and ensure `.run` files in `dist/` are included in snapshot upload and tag release.
- [x] T005 Test snapshot build end-to-end: trigger workflow, confirm `.run` files appear in the uploaded artifact bundle.
- [ ] T006 Test tag build end-to-end: push a test tag, confirm `.run` files are attached to the GitHub Release.
- [x] T007 Test fresh install: extract `.run` on a clean Linux system, confirm all files land at FHS paths with correct permissions and `config.yaml` is seeded.
- [x] T008 Test upgrade install: install once, modify `/etc/nixstasis/frpc.toml` and `/etc/nixstasis/config.yaml`, install again, confirm configs are preserved and binaries are replaced.
- [x] T009 Test `--force-config`: install with existing configs, re-install with `--force-config`, confirm both `frpc.toml` and `config.yaml` are overwritten.
- [x] T010 Update `packages/client/README.md` to document `.run` installer usage, extraction with `--noexec --target`, and config seeding behavior.
- [x] T011 Update `docs/src/planned-features.md` status from `in-spec` to `in-progress` when implementation starts, then to `completed` during close-out.
- [ ] T999 Close out the feature by confirming docs, scripts, CI workflow, and delivered behavior agree.
