# Client Release Notes

GoReleaser is the supported client release entrypoint for this feature.

## Pinning policy

- The bundled `frpc` binary must come from an immutable, checksum-verified source.
- Release automation must fail if the staged `frpc` source is not explicitly pinned.
- Generated `.deb`, `.rpm`, and archive assets must install `frpc` to `/usr/libexec/nixstasis/frpc`.

## Verification

- Run `goreleaser release --snapshot --clean` from `packages/client`.
- Run `./build/bin/verify_artifacts.sh` after each snapshot build.
