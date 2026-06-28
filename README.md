# devops-pipeline

A reusable 3-level CI/CD pipeline for Forgejo repositories. Drop it into any
new project and get:

- **Level 1** (push to `main`): build → test → bump version → cut Forgejo release → build Linux bottles (x86_64 + arm64) → update Homebrew formula → push to external tap → tidy branches.
- **Level 2** (push to `devops`): build → test → open PR to `main` → close issues via `Fixes #N` markers.
- **Level 3** (issue opened with `bug`/`enhancement` label): triage via AI → AI edits the codebase → open `issue-N → devops` PR → close the issue.

The AI integration uses the local `opencode` CLI with the model of your choice
(default: runner-configured). No external CI service required.

## How to use this template

You have **two options** — pick whichever is more convenient.

### Option A — "Use this template" button (Forgejo web UI)

1. In Forgejo, navigate to https://forge.akinus21.com/akinus/devops-pipeline.
2. Click the **⋯** menu (top right) → **Use this template** (or the equivalent button in your Forgejo version).
3. Pick the new repo's owner + name, set visibility, and create.
4. Clone your new repo locally:
   ```bash
   git clone ssh://git@forge.akinus21.com:2222/<owner>/<new-repo>.git ~/projects/<new-repo>
   cd ~/projects/<new-repo>
   ```
5. The `.forgejo/workflows/` + `install.sh` are already in the repo — nothing else to copy. Skip to [Configure the new repo](#configure-the-new-repo).

### Option B — Manual install via the install script

If you already have a repo (perhaps with existing code) and want to add the pipeline:

```bash
# Download the install.sh + .forgejo/ from the template repo into /tmp
curl -sSL https://forge.akinus21.com/akinus/devops-pipeline/archive/main.tar.gz \
  | tar xz -C /tmp --strip-components=1 devops-pipeline

# Run the installer — it copies the workflow files into your repo,
# creates the 'devops' branch, commits, and pushes.
bash /tmp/install.sh ~/projects/<new-repo>
```

Notes:
- The archive directory is named `devops-pipeline/` (no branch suffix). The `--strip-components=1 devops-pipeline` extracts it directly into `/tmp`.
- For self-hosted Forgejo on a non-default host, replace `forge.akinus21.com/akinus/devops-pipeline` with your `<host>/<owner>/devops-pipeline`.

Or if you have this template cloned somewhere already:

```bash
~/projects/devops-pipeline/install.sh ~/projects/<new-repo>
```

To install the Homebrew formula stub too (only relevant for CLI tools with
homebrew distribution):

```bash
WITH_FORMULA=1 ~/projects/devops-pipeline/install.sh ~/projects/<new-repo>
```

To use non-default branch names:

```bash
DEV_BRANCH=staging MAIN_BRANCH=production \
  ~/projects/devops-pipeline/install.sh ~/projects/<new-repo>
```

## Configure the new repo

After the pipeline files are in place, you need to set a few things in your
new repo's Forgejo UI:

1. **Settings → Actions → Secrets** — add the secrets the pipeline needs:
   - `TAP_TOKEN` — *only if you use a homebrew tap*. Personal API token with `write:repository` scope, scoped to your tap repo. If you don't distribute via homebrew, skip this.

2. **Settings → Actions → Variables** — optional overrides:
   - `OPENCODE_MODEL` — model ID passed to `opencode run --model`. Empty = runner default.
   - `BREW_TAP_ENABLED` — `true` to enable the formula + bottle pipeline.
   - `BREW_TAP_REPO` — `owner/tap-repo-name`.
   - `BREW_TAP_BRANCH` — tap branch (default `main`).
   - `BOT_NAME` / `BOT_EMAIL` — git committer identity for bot commits.
   - `MAIN_BRANCH` / `DEVOPS_BRANCH` / `ISSUE_BRANCH_PREFIX` — only set if your branch names differ from the defaults (`main`, `devops`, `issue-`).

3. **Runner prerequisites** (set on the Forgejo runner host, not in the repo):
   - A runner registered with the label **`rust-ci`** pointing at a Docker image that has `rustc`, `cargo`, `opencode`, `jq`, `git`, and `curl` pre-installed. The pipeline uses `runs-on: rust-ci` for that reason. A reference image is the akclip `Dockerfile.rust-ci`.
   - `forgejo-actions` auto-token enabled on the runner, so `${{ github.token }}` resolves.

## What you'll see once it's running

- **First push to `devops`** — triggers Level 2: builds your code, opens a PR to `main`. Merge it.
- **Merge to `main`** — triggers Level 1: bumps version, cuts a release, builds bottles, updates formula, tidies branches.
- **Open a `bug` or `enhancement` issue** — triggers Level 3: opencode triages, edits files on a new `issue-N` branch, opens a PR to `devops`. The issue is auto-closed when the PR opens.
- **Merge that PR to `devops`**, then merge the devops→main PR, and a new release ships.

## Customizing the pipeline

The pipeline auto-detects language from `Cargo.toml`, `go.mod`, `package.json`,
or `pyproject.toml` / `setup.py`. For anything else (Make, Bazel, etc.) edit
the `case "${{ needs.detect.outputs.language }}"` blocks in the three workflow
files.

To change the version bump rule (currently `MAJOR.MINOR.PATCH+1`), edit the
`Bump version` step in `level1-main.yml`.

To change what gets triaged / how fixes are written, edit the prompt templates
in the heredoc blocks under the `triage` and `Run opencode fix` steps of
`level3-issues.yml`.

## Files in this template

```
.
├── .forgejo/workflows/
│   ├── level1-main.yml       # Level 1: main branch pipeline (release + bottles + formula + tidy)
│   ├── level2-devops.yml     # Level 2: devops branch pipeline (build + PR to main + close issues)
│   └── level3-issues.yml     # Level 3: issue-driven pipeline (triage + AI fix + PR)
├── install.sh                # One-shot installer for adding this pipeline to another repo
├── AGENTS.md                 # Detailed design notes for AI agents editing the pipeline
└── README.md                 # This file
```

## Validated end-to-end

This pipeline was developed and validated on
[akinus/akclip](https://forge.akinus21.com/akinus/akclip). Level 1, Level 2,
and Level 3 all completed a full end-to-end run on June 28, 2026 — including
an AI-generated 23-test suite added via a `enhancement` issue.