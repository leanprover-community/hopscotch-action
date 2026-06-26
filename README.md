# hopscotch-action
A reusable GitHub Action that wraps the [`hopscotch`](https://github.com/leanprover-community/hopscotch) CLI to:

1. **Identify the culprit of an incompatibility**. Bisect an upstream dependency's commit history to find a commit that introduced the incompatibility. The build check can be extended with `lake test` and `lake lint` verify steps.
2. **Open a bump PR**. When the build passes (or after finding the last-good commit), automatically open or update a pull request to advance the manifest pin.
3. **Open a fix PR**. Pin the manifest to the first-known-bad commit on a per-FKB branch so maintainers can `gh pr checkout` and reproduce the break locally.
4. **Track incompatibilities with an issue**. After finding a culprit, automatically open or update an issue to report the breaking commit.
5. **Apply automated fixes**. hopscotch detects breakage caused by module deprecations and proposes the import rewrites that repair it. With `apply-fixes`, the action runs `hopscotch fix apply` and folds those rewrites into the PR, so a fix PR becomes ready to merge once its CI is green.

The action runs in one of two modes selected by `pin-to`:

- `pin-to: last-good` (default) — opens / updates a **bump PR** advancing the manifest to the last passing commit, and manages a tracking issue.
- `pin-to: first-bad` — opens a **fix PR** pinning the manifest to the first-known-bad commit (per-FKB-SHA branch). No tracking issue in this mode — the PR itself surfaces the FKB context.

Run the action twice (once per mode) on the same workflow if you want both artifacts.

Note: for repeatability, the default version of `hopscotch` used by this action is fixed, currently at **v2.0.0**. You can configure the version (to `latest` or otherwise) using the `hopscotch-version` parameter described below.

## Quickstart

```yaml
name: hopscotch

on:
  schedule:
    - cron: "0 18 * * *"   # daily at 18:00 UTC
  workflow_dispatch:

jobs:
  run:
    runs-on: ubuntu-latest
    permissions:
      contents: write       # push bump branch
      pull-requests: write  # open / update bump PR
      issues: write         # open / close tracking issue
    steps:
      - uses: actions/checkout@v6

      - uses: leanprover-community/hopscotch-action@v1
        with:
          dependency: mathlib
          to: master
          pr-base: main
          pr-labels: "dependencies,auto-bump"
```

The job summary shows the outcome. If the upstream breaks the build a GitHub issue is opened automatically; this issue is closed when the build recovers (namely: if a subsequent run of this action succeeds against the target commit).

## How it works

The action performs the following steps on each run:

1. **Install elan** (skipped if already present) and add `~/.elan/bin` to `PATH`
2. **Install hopscotch** binary
3. **Read the current pin** from `lake-manifest.json` (becomes the lower bound).
4. **Clean** any leftover hopscotch session state.
5. **Run** `hopscotch dep <name> --from <prev-pin> --to <target> --keep-last-good [--test] [--lint] [extra-args]`.
6. **Parse** `.lake/hopscotch/results.json` (hopscotch's public, versioned output) to determine outcome, culprit SHA, last-good SHA, the failing stage, the new manifest pin, and any proposed automated fixes / deprecation advisories.
7. **Apply automated fixes** with `hopscotch fix apply` when `apply-fixes` is enabled and there is something safe to apply (skipped otherwise).
8. **Open / update a bump PR** when the dependency can be advanced (skipped if `open-pr: false`).
9. **Write a job summary** and manage a GitHub tracking issue (skipped if `open-issue: false`).

With `--keep-last-good` a single hopscotch invocation both finds the culprit *and* leaves the manifest pinned to the last passing commit, so one workflow handles regression detection and bump-PR creation together.

`hopscotch dep` always runs its automated-fix detection at the run's conclusion (pass `--no-auto-fix` via `extra-args` to disable it). Detection never modifies your workspace; its findings are surfaced in the PR / issue body and the `proposed-fix-count` / `deprecated-import-count` outputs whether or not `apply-fixes` is set.

## Issue and PR lifecycle

### `pin-to: last-good` (default — bump PR + tracking issue)

The action maintains two artifacts across runs:

- a **tracking issue** that is open while a regression is active and closed when the build recovers, and
- a **bump PR** on a single force-pushed branch that advances the manifest pin whenever it moves (to the last-good commit on failure, to the full target on success).

| Outcome | Issue state before | Issue action | PR action |
|---|---|---|---|
| `passed` | none | — | open / update if pin changed |
| `passed` | open | close with recovery comment | open / update if pin changed |
| `incompatible` | none | **create** | open / update to last-good commit |
| `incompatible` | open | **update** body + title | open / update to last-good commit |
| `skipped` | any | — (nothing was built) | — |
| `tool-error` | any | — (hopscotch failed) | — |

When the remote branch already holds an identical tree at HEAD and an open PR points at it, the push is skipped and `pr-action` is reported as `up-to-date`. This avoids churning CI and the PR timeline on sub-daily reruns.

### `pin-to: first-bad` (fix PR only)

The action opens a **fix PR** on a per-FKB-SHA branch (default `hopscotch/fix-<short>`). Maintainers can `gh pr checkout` the PR to reproduce the break locally. No tracking issue is opened in this mode.

| Outcome | Fix-PR action |
|---|---|
| `passed` | close all open fix PRs with a recovery comment |
| `incompatible` (new FKB) | open a new fix PR on the per-FKB branch; close stale fix PRs for prior FKBs |
| `incompatible` (same FKB, remote tree matches HEAD) | no-op; reports the existing PR (`pr-action: up-to-date`) |
| `incompatible` (same FKB, maintainer pushed commits) | no-op; the maintainer's commits are preserved (`pr-action: up-to-date`) |
| `incompatible` (same FKB, tree differs and branch is bot-owned) | force-push, update PR title / body |
| `skipped` | — |
| `tool-error` | — |

**Maintainer WIP on fix PRs.** The action force-pushes its bump / fix branches by default. In fix-PR mode this would clobber any commits the maintainer pushed on top of the fix branch — so before pushing, the action checks the remote HEAD's committer email and skips the push when it doesn't match `git-user-email` (default `github-actions[bot]@…`). This is heuristic, not bulletproof: a maintainer who pushes to the branch as the bot identity, or a force-push that rewrites history, will not be detected. If you customize `git-user-name` / `git-user-email`, keep the maintainer's local identity distinct from the bot's.

## Automated fixes (module deprecations)

A common source of upstream breakage is a **module deprecation**: a dependency deletes a module (splitting or moving its contents) and leaves a `deprecated_module` shim re-exporting the new location. Every such break is repaired the same mechanical way — rewrite the downstream `import` to the module(s) the shim points at.

hopscotch detects these on every `dep` run and records two kinds of result, both surfaced by this action:

- **Proposed fixes** — import rewrites that repair the failure boundary. Reported in `proposed-fix-count` and in the PR / issue body.
- **Deprecation advisories** — imports that still build today but resolve through a live shim and will break when it is deleted upstream. Reported in `deprecated-import-count`.

When detection can't propose a repair (a genuine removal with no replacement shim), it records a human-readable note instead, which the tracking issue surfaces.

`apply-fixes` controls whether the action acts on these by running `hopscotch fix apply`:

| `apply-fixes` | Effect |
|---|---|
| `none` (default) | Detect and report only — no source files are touched. |
| `boundary` | Apply only the break-repairing proposals (`--no-advisories`). |
| `all` | Also apply deprecation-hygiene advisories. |

The applied rewrites are committed onto the PR branch alongside the pin change, so the PR's own CI validates the repair.

**Where each kind of fix is applied.** A boundary proposal rewrites an import to a module that only exists *at or after* the break, so it is only applied where the manifest sits at the break — i.e. **`pin-to: first-bad`** (where it turns the reproduction PR into a mergeable "fix breaking changes" PR). In **`pin-to: last-good`** the manifest sits *before* the break, so the action applies only advisories, and only on a fully-green run, folding deprecation hygiene into the bump PR. Either way the proposals/advisories/notes are still reported.

For the canonical CI flow: run `pin-to: first-bad` with `apply-fixes: boundary` on a schedule. Each run opens (or refreshes) a ready-to-merge fix PR for the current break; merge it, and the next run advances past the repaired breakage to find the next one.

## Action inputs

| Input | Default | Description |
|---|---|---|
| `dependency` | *(required)* | Lakefile require name, e.g. `mathlib`. |
| `from` | *(manifest pin)* | Exclusive lower bound for the bisect range. Defaults to the current rev in `lake-manifest.json`. |
| `to` | *(upstream HEAD)* | Inclusive upper bound. Defaults to the upstream default-branch HEAD. |
| `project-dir` | `.` | Path to the Lean project root. |
| `extra-args` | `` | Extra arguments passed verbatim to `hopscotch dep`. Single- or multi-line; each line is word-split on whitespace. Use for flags without a dedicated input (`--commits-file`, `--git-url`, `--config-file`, `--no-auto-fix`). |
| `run-tests` | `false` | Add a `lake test` verify step to each probe (hopscotch `--test`). |
| `run-lint` | `false` | Add a `lake lint` verify step to each probe (hopscotch `--lint`). |
| `build-args` | `` | Extra args for `lake build` (hopscotch `--build-args`). E.g. `--wfail` to treat warnings as errors. |
| `test-args` | `` | Extra args for `lake test` (hopscotch `--test-args`). |
| `lint-args` | `` | Extra args for `lake lint` (hopscotch `--lint-args`). |
| `hopscotch-version` | `v2.0.0` | Release tag (e.g. `v2.0.0`) or `"latest"` to always use the newest release. |
| `max-window-size` | `3000` | Abort if the range contains more commits than this. |
| | | |
| | | |
| `pin-to` | `last-good` | `last-good` (bump PR) or `first-bad` (fix PR). |
| `apply-fixes` | `none` | Apply hopscotch's automated import fixes into the PR via `hopscotch fix apply`: `none`, `boundary` (proposals only), or `all` (also advisories). See [Automated fixes](#automated-fixes-module-deprecations). |
| `open-pr` | `true` | Open / update a PR when the pin changes. |
| `pr-branch` | *(mode-dependent)* | LKG mode: literal branch (default `hopscotch/bump`). FKB mode: prefix, actual branch is `<prefix>-<fkb-short7>` (default `hopscotch/fix`). |
| `pr-base` | *(default branch)* | Base branch for the PR. |
| `pr-labels` | `` | Comma-separated labels for the PR. |
| `reviewers` | `` | Comma-separated GitHub users or team slugs to request review from. |
| | | |
| | | |
| `open-issue` | `true` | Open a tracking GitHub issue on culprit / recovery. Ignored in FKB mode. |
| `issue-labels` | `` | Comma-separated labels for the tracking issue. |
| | | |
| | | |
| `github-token` | `${{ github.token }}` | Token for API calls (PR list, issue ops). |
| `pr-token` | *(falls back to `github-token`)* | Token used to push the PR branch. The default `GITHUB_TOKEN`'s pushes don't trigger downstream workflow runs on the PR — pass a GitHub App installation token here to make CI run on bump / fix PRs. |
| `git-user-name` | `github-actions[bot]` | git `user.name` for the bump / fix commit. |
| `git-user-email` | `41898282+github-actions[bot]@users.noreply.github.com` | git `user.email` for the bump / fix commit. |

## Outputs

| Output | Description |
|---|---|
| `outcome` | `passed` \| `incompatible` \| `skipped` \| `tool-error` |
| `culprit-commit` | SHA of the first failing upstream commit. |
| `last-good-commit` | SHA of the last passing upstream commit. |
| `target-commit` | SHA that `--to` resolved to. |
| `failure-stage` | The step that failed when `incompatible`: `lake update` \| `lake build` \| `lake test` \| `lake lint` \| `git cleanliness check`. Empty otherwise. |
| `proposed-fix-count` | Number of automated boundary repairs hopscotch proposed. |
| `deprecated-import-count` | Number of live-shim deprecation advisories recorded. |
| `fixes-applied` | `true` when `apply-fixes` ran `hopscotch fix apply` and edited the tree. |
| `previous-pin` | Manifest rev before this run. |
| `new-pin` | Manifest rev after this run. |
| `summary-md` | Raw Markdown summary generated by hopscotch |
| | | |
| | | |
| `pr-number` | PR number (empty when not opened). |
| `pr-url` | PR URL. |
| `pr-action` | `created`, `updated`, `up-to-date`, or `none`. |
| | | |
| | | |
| `issue-number` | Tracking issue number. |
| `issue-url` | Tracking issue URL. |

## Permissions required

| Permission | Needed for |
|---|---|
| `contents: write` | Pushing the bump branch |
| `pull-requests: write` | Creating / updating the bump PR |
| `issues: write` | Managing the tracking issue |

Remove permissions you don't need (e.g. omit `issues: write` and set `open-issue: false` if you don't want tracking issues).

## Customized usage

### Culprit-only scan and issue tracking (no bump PR)

```yaml
- uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    open-pr: false
```

### Bump to an explicit target, no issue tracking

```yaml
- uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    to: v4.20.0
    open-issue: false
```

### Read the outcome in a later step

```yaml
- id: hs
  uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: batteries

- if: steps.hs.outputs.outcome == 'incompatible'
  run: |
    echo "Broken by: ${{ steps.hs.outputs.culprit-commit }}"
    echo "Last good: ${{ steps.hs.outputs.last-good-commit }}"
```

### Open both a bump PR and a fix PR

Two jobs in the same workflow — each runs the action in its own mode.

```yaml
jobs:
  bump:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - uses: actions/checkout@v6
      - uses: leanprover-community/hopscotch-action@v1
        with:
          dependency: mathlib
          to: master
          pin-to: last-good      # default — bump PR + tracking issue

  fix:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v6
      - uses: leanprover-community/hopscotch-action@v1
        with:
          dependency: mathlib
          to: master
          pin-to: first-bad      # fix PR pinning manifest to the FKB
```

### Trigger CI on bump / fix PRs

By default the PR is pushed using `GITHUB_TOKEN`, which does **not** trigger downstream workflow runs on the PR it creates. To make CI run on the PR, pass a GitHub App installation token via `pr-token`:

```yaml
- uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    pr-token: ${{ steps.app-token.outputs.token }}
```

### Multi-line extra-args

```yaml
- uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    extra-args: |
      --scan-mode linear
      --allow-dirty-workspace
```

### Verify with tests and lint (and fail on warnings)

Extend each probe beyond `lake build`. A commit that builds but fails its
tests (or trips a deprecation warning under `--wfail`) is then treated as the
break. `failure-stage` tells you which step failed.

```yaml
- uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    run-tests: true
    run-lint: true
    build-args: --wfail   # treat warnings (incl. deprecations) as errors
```

### Auto-fix breaking changes (ready-to-merge fix PR)

When the break is a module deprecation, apply hopscotch's proposed import
rewrites so the fix PR is mergeable once its CI is green. Run on a schedule:
each run refreshes the fix PR for the current break; merge it and the next run
moves on to the next one.

```yaml
- uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    to: master
    pin-to: first-bad
    apply-fixes: boundary       # apply only the break-repairing rewrites
    pr-token: ${{ steps.app-token.outputs.token }}  # so the PR's CI runs
```

Branch on the outputs to handle the non-repairable case yourself:

```yaml
- id: hs
  uses: leanprover-community/hopscotch-action@v1
  with:
    dependency: mathlib
    pin-to: first-bad
    apply-fixes: boundary

- if: steps.hs.outputs.outcome == 'incompatible' && steps.hs.outputs.proposed-fix-count == '0'
  run: echo "Genuine break at ${{ steps.hs.outputs.culprit-commit }} — needs manual work"
```

## Development

The action is a composite of small bash scripts under `scripts/`; each step in
`action.yml` is a thin shim that sets env vars and invokes one script.
Non-trivial scripts are unit-tested with [bats](https://github.com/bats-core/bats-core).

```
scripts/
  *.sh                     # one script per stage
  lib/                     # shared helpers (commit links, label handling, ...)
tests/
  *.bats                   # bats test suites
  fixtures/                # sample results.json / lake-manifest.json for tests
  stubs/                   # stand-in executables for gh, hopscotch, etc.
```

Run the test suite locally:

```
bats tests/
shellcheck scripts/*.sh scripts/lib/*.sh
```

## Platform support

| Platform | Supported |
|---|---|
| Linux x86_64 | ✅ |
| macOS x86_64 | ✅ |
| macOS arm64 (Apple Silicon) | ✅ |
| Windows x86_64 | ✅ |
