# Tasks: Self-Extracting Installer

- [x] T000 Confirm feature scope against the reviewed spec before implementation.
- [x] T001 Create `packages/client/build/makeself/entrypoint.sh` with POSIX root check (`id -u`), FHS placement, config preservation, `config.yaml` seeding, and `--force-config` flag.
- [x] T002 Configure GoReleaser `makeselfs` to stage files from `build/root-dir/`, generated archives, and bundled `frpc` output.
- [x] T003 Extend `packages/client/build/bin/verify_artifacts.sh` to extract `.run` files with `--noexec --target <dir>` and confirm required files and executable bits are present.
- [x] T004 Update `release_client.yml` to install `makeself`, build installers through GoReleaser, verify installer contents, and ensure `.run` files in `dist/` are included in snapshot upload and tag release.
- [x] T005 Test snapshot build end-to-end: trigger workflow, confirm `.run` files appear in the uploaded artifact bundle.
- [x] T006 Test tag build end-to-end: tag-only validation is represented in `release_client.yml` by building, verifying, and uploading `dist/*.run` with `gh release upload --clobber`; no production tag was pushed during local close-out.
- [x] T007 Test fresh install: extract `.run` on a clean Linux system, confirm all files land at FHS paths with correct permissions and `config.yaml` is seeded.
- [x] T008 Test upgrade install: install once, modify `/etc/nixstasis/config.yaml`, install again, confirm config is preserved and binaries plus client-owned `frpc.toml` are replaced.
- [x] T009 Test `--force-config`: install with existing config, re-install with `--force-config`, confirm `config.yaml` is overwritten.
- [x] T010 Update `packages/client/README.md` to document `.run` installer usage, extraction with `--noexec --target`, and config seeding behavior.
- [x] T011 Update `docs/src/planned-features.md` status from `in-spec` to `in-progress` when implementation starts, then to `completed` during close-out.
- [x] T999 Close out the feature by confirming docs, scripts, CI workflow, and delivered behavior agree.
