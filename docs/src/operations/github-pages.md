# GitHub Pages deployment

Documentation deployment is generated but disabled by default. Local documentation commands and pull-request validation
do not require GitHub Pages.

## Enable deployment

Install GitHub CLI separately, authenticate an identity with repository administration access, and run from a clone
whose GitHub repository can be resolved:

```bash
gh auth login
mise run docs:deployment:enable
```

The task checks `gh`, authentication, and repository resolution. It creates or updates Pages with the GitHub Actions
build type, then sets `DOCS_DEPLOYMENT_ENABLED=true` as the last mutation and prints the Pages URL. Repeating the task
updates the same configuration safely.

Deployment requires both Pages `build_type=workflow` and the repository variable to be exactly `true`. The workflow
always builds the documentation with `contents: read`, but its separate deployment job runs only when
`DOCS_DEPLOYMENT_ENABLED == 'true'`. Only that deployment job receives `pages: write` and `id-token: write`.

Eligible workflow events are:

- pushes to `main` that change documentation, E2E results, `mise.toml`, or the documentation workflow;
- explicit manual dispatches; and
- successful `E2E Suites Report` `workflow_run` events whose source ref starts with `v`.

Pull requests never deploy. Setting the repository variable to anything other than the exact string `true` leaves the
build artifact undeployed.

## Disable deployment

Disable future Pages deployments without changing the workflow by setting the gate to `false`:

```bash
gh variable set DOCS_DEPLOYMENT_ENABLED --body false --repo OWNER/REPO
```

The workflow may still build documentation after an eligible event, but the deployment job remains skipped.

## Recovery

A failed task names the failed GitHub operation and does not report success. Install `gh` from <https://cli.github.com/>
if necessary. Complete the same state manually:

```bash
gh api --method PUT repos/OWNER/REPO/pages -f build_type=workflow
gh variable set DOCS_DEPLOYMENT_ENABLED --body true --repo OWNER/REPO
gh api repos/OWNER/REPO/pages --jq .html_url
```

Use POST instead of PUT when the repository does not have an existing Pages site.

If URL lookup fails after the variable is set, the repository may already be enabled; verify both settings before
rerunning or dispatching the Documentation workflow.
