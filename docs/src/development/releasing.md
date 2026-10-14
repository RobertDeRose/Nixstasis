# Releasing

Releases are cut from `dev` and published on `main`. `main` only ever moves by
fast-forward to a validated `dev` commit, so both branches share identical,
signed history and no version-bump commit is ever created.

## How a release works

Run the **Release** workflow (`.github/workflows/release.yml`) from the Actions
tab on the `dev` branch, or from the command line:

```bash
gh workflow run release.yml --ref dev
```

The workflow then runs these jobs in order:

1. **Plan** checks that `main` is an ancestor of the `dev` commit, computes the
   next version with `cog bump --auto --dry-run`, and renders the release notes
   with `cog changelog`. The version and notes appear in the run summary.
2. **Validate** runs the same validation workflow as pull requests against that
   exact commit: repository checks, the server test suite, and the client test
   suite.
3. **Fast-forward main and tag** waits for approval through the `release`
   environment. After approval it pushes the commit to `main` with a plain
   (non-force) push, which GitHub rejects unless it is a fast-forward, then
   pushes an annotated `vX.Y.Z` tag and creates a draft GitHub release with the
   cocogitto notes.
4. **Build** calls the server, Caddy, and FRPS image workflows and the client
   release workflow with the version. Images are pushed to GHCR as
   `X.Y.Z`, `X.Y`, `latest`, and `sha-<commit>`. Client packages and installers are uploaded to the
   draft release.
5. **Publish release** turns the draft into a published release once every
   build has succeeded.

If the run is rejected or fails before the approval step, nothing has changed.
If a job fails after approval, `main` and the tag may already exist and the
release stays a draft. Rerun the failed jobs from the same run: the publish job
reuses an existing tag only when it marks the same commit and skips an existing
draft release.

The fast-forward of `main` is an ordinary push, so workflows triggered by
pushes to `main` (the E2E report and documentation site) also run.

## Versions

Cocogitto derives the version from Conventional Commits since the latest `v*`
tag, using `cog.toml`. The version is never committed. Builds receive it as
an input:

- the client gets it from GoReleaser's default `-X main.version` linker flag and
  reports it with `nixstasis --version`;
- the server reads `NIXSTASIS_VERSION` in `mix.exs`, which the server image
  passes as a Docker build argument;
- local `go build` reports `dev`, branch CI snapshots report
  `0.0.0-snapshot-<commit>`, and non-release server builds report `0.0.0-dev`.

Branch pushes still build images and client snapshots for verification, but
only the Release workflow publishes images or release artifacts. Manual
`workflow_dispatch` image builds with `push` enabled remain available for
one-off testing and are tagged with the branch and commit only.

## Repository setup

The workflow depends on this one-time GitHub configuration:

- A `release` environment with yourself (or the maintainers) as required
  reviewers and deployments limited to the `dev` branch. The approval request
  appears on the run and shows the planned version and notes.
- A deploy key with write access whose private key is stored as the
  `RELEASE_DEPLOY_KEY` secret on the `release` environment, so only approved
  release jobs can read it.
- A branch ruleset on `main` that blocks direct updates, deletion, and force
  pushes, with the deploy key as the only bypass actor.
- A tag ruleset on `v*` that blocks creation, update, and deletion, with the
  same bypass.

The deploy key's private half exists only in the `RELEASE_DEPLOY_KEY`
environment secret and is never needed elsewhere. To rotate it, or after a
suspected exposure, delete the deploy key from the repository settings,
generate a new ed25519 key pair, add its public half as a write-enabled deploy
key, and overwrite the secret with the private half:

```bash
gh repo deploy-key add release_deploy_key.pub --allow-write \
  --title 'Release workflow (main + v* tags)'
gh secret set RELEASE_DEPLOY_KEY --env release < release_deploy_key
```

Delete the local key files afterwards. The rulesets allow deploy keys as a
class, so rotation needs no ruleset change.

The workflow pushes `main` and the tag with the deploy key rather than
`GITHUB_TOKEN` because the rulesets can grant a deploy key a bypass. It calls
the build workflows directly, rather than letting the tag push trigger them, so
one run owns the whole release and the GitHub release is published only after
every build succeeds.
