#!/usr/bin/env bash
# install.sh - drop the akclip-style CI pipeline into any project
#
# Usage:
#   ./install.sh /path/to/target-repo
#   ./install.sh git@forge.akinus21.com:owner/project.git
#   ./install.sh https://github.com/owner/project.git
#
# What it does:
#   1. Resolves the target (existing path or clones a git URL).
#   2. Creates a `devops` branch off the default branch if missing.
#   3. Copies .forgejo/workflows/level{1,2,3}-*.yml
#      into the target repo.
#   4. Optionally writes a Formula/<name>.rb stub.
#   5. Commits + pushes the changes.
#
# Defaults are all overridable via env vars:
#   DEV_BRANCH     - staging branch (default: devops)
#   MAIN_BRANCH    - target branch (default: main)
#   BOT_NAME       - git committer name (default: devops-bot)
#   BOT_EMAIL      - git committer email (default: devops-bot@akinus21.com)
#   REMOTE         - git remote name (default: origin)
#   WITH_FORMULA   - if set to 1, write a Formula/<name>.rb stub

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_SRC="$SCRIPT_DIR/.forgejo/workflows"

DEV_BRANCH="${DEV_BRANCH:-devops}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
ISSUE_BRANCH_PREFIX="${ISSUE_BRANCH_PREFIX:-issue-}"
BOT_NAME="${BOT_NAME:-devops-bot}"
BOT_EMAIL="${BOT_EMAIL:-devops-bot@akinus21.com}"
REMOTE="${REMOTE:-origin}"
WITH_FORMULA="${WITH_FORMULA:-0}"

# ---------- arg parsing ----------
if [ $# -lt 1 ]; then
  cat <<EOF >&2
usage: $0 <target>

target can be:
  - a local directory path        /path/to/repo
  - an SSH git URL                git@host:owner/repo.git
  - an HTTPS git URL              https://host/owner/repo.git

env overrides:
  DEV_BRANCH, MAIN_BRANCH, BOT_NAME, BOT_EMAIL, REMOTE, WITH_FORMULA
EOF
  exit 2
fi

TARGET="$1"
WORKDIR=""

if [[ "$TARGET" =~ ^(https?|git|ssh):// ]] || [[ "$TARGET" =~ ^git@ ]]; then
  WORKDIR="$(mktemp -d -t pipeline-install-XXXXXX)"
  echo "Cloning $TARGET into $WORKDIR ..."
  git clone --depth 50 "$TARGET" "$WORKDIR"
elif [ -d "$TARGET" ]; then
  WORKDIR="$(cd "$TARGET" && pwd)"
  echo "Using existing repo at $WORKDIR"
else
  echo "Target is neither a directory nor a recognized URL: $TARGET" >&2
  exit 1
fi

cd "$WORKDIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $WORKDIR" >&2
  exit 1
fi

# Make sure git committer identity is set
git config user.name  "$BOT_NAME"
git config user.email "$BOT_EMAIL"

# Detect the default branch: prefer origin/HEAD, fall back to the
# current branch, fall back to the env override.
set +e
DEFAULT_BRANCH=$(git symbolic-ref --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null \
  | sed "s|^$REMOTE/||")
set -e
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || echo "$MAIN_BRANCH")
fi
echo "Default branch: $DEFAULT_BRANCH"

# ---------- branch setup ----------
git fetch "$REMOTE" --prune >/dev/null 2>&1 || true

# Make sure dev branch exists locally + remotely
if git show-ref --verify --quiet "refs/heads/$DEV_BRANCH"; then
  echo "Dev branch '$DEV_BRANCH' already exists locally."
elif git ls-remote --heads "$REMOTE" "$DEV_BRANCH" 2>/dev/null | grep -q .; then
  echo "Checking out existing remote '$DEV_BRANCH'..."
  git checkout "$DEV_BRANCH"
else
  echo "Creating '$DEV_BRANCH' off '$DEFAULT_BRANCH'..."
  git checkout "$DEFAULT_BRANCH" || git checkout -b "$DEFAULT_BRANCH"
  git checkout -b "$DEV_BRANCH"
  git push "$REMOTE" "$DEV_BRANCH" >/dev/null 2>&1 || echo "  (will retry after copy)"
fi

# Check out dev branch to commit the workflow files there
git checkout "$DEV_BRANCH" 2>/dev/null || git checkout -b "$DEV_BRANCH"

# ---------- copy workflow files ----------
mkdir -p .forgejo/workflows
for f in level1-main.yml level2-devops.yml level3-issues.yml; do
  cp "$WORKFLOW_SRC/$f" ".forgejo/workflows/$f"
  echo "Copied .forgejo/workflows/$f"
done

# ---------- template branch names ----------
# The workflows ship with literal branch names (Forgejo Actions'
# YAML parser doesn't accept template expressions in on.push.branches).
# Replace them here so the install honours env overrides.
ISSUE_PREFIX_RE=$(printf '%s' "$ISSUE_BRANCH_PREFIX" | sed 's/[][\\.^$*]/\\&/g')
sed -i "s|branches: \\[main\\] *#.*|branches: [$MAIN_BRANCH]|" .forgejo/workflows/level1-main.yml
sed -i "s|branches: \\[devops\\] *#.*|branches: [$DEV_BRANCH]|" .forgejo/workflows/level2-devops.yml
sed -i "s|branches: \\[issue-\\*\\] *#.*|branches: [${ISSUE_PREFIX_RE}*]|" .forgejo/workflows/level3-issues.yml
echo "Templated branch names: main=$MAIN_BRANCH devops=$DEV_BRANCH issue-prefix=$ISSUE_BRANCH_PREFIX"

# ---------- optional Formula stub ----------
REPO_NAME=$(basename "$(git rev-parse --show-toplevel)" .git 2>/dev/null \
             || git config --get remote.origin.url \
             | sed 's|.*[:/]||; s|\.git$||')
if [ "$WITH_FORMULA" = "1" ]; then
  mkdir -p Formula
  CLASS=$(echo "$REPO_NAME" | awk -F'[-_]' '{ for (i=1; i<=NF; i++) $i = toupper(substr($i,1,1)) substr($i,2); print }' OFS='')
  cat > "Formula/${REPO_NAME}.rb" <<EOF
class ${CLASS} < Formula
  desc "TODO: real description"
  homepage "TODO"
  url "https://example.com/release.tar.gz"
  version "0.0.0"
  sha256 "TODO"

  def install
    bin.install "$REPO_NAME"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/$REPO_NAME --version")
  end
end
EOF
  echo "Wrote Formula/${REPO_NAME}.rb stub (edit it)"
fi

# ---------- commit + push ----------
git add -A
if git diff --staged --quiet; then
  echo "No changes to commit (workflows already present and identical)."
else
git commit -m "ci: install 3-level pipeline workflows"
git push "$REMOTE" "$DEV_BRANCH" >/dev/null 2>&1 || echo "  (push skipped - no remote)"
fi

echo
echo "=== Installed ==="
echo "  Workflows: .forgejo/workflows/{level1-main,level2-devops,level3-issues}.yml"
echo "  Dev branch: $DEV_BRANCH"
echo "  Default branch: $DEFAULT_BRANCH"
echo
echo "Next steps:"
echo "  1. In your Forgejo repo UI, add the secret TAP_TOKEN (Settings -> Actions -> Secrets)."
echo "     TAP_TOKEN is a personal API token with 'write:repository' scope."
echo "     It is ONLY used to push the rendered formula to an EXTERNAL homebrew tap repo."
echo "     In-repo operations (releases, PRs, branch deletion) use the forgejo-actions"
echo "     auto-token via \${{ github.token }} - no extra secret required for those."
echo "     If you don't use a homebrew tap, you can skip TAP_TOKEN entirely."
echo "  2. (Optional) Set repo variables under Settings -> Actions -> Variables:"
echo "       OPENCODE_MODEL   - optional override for 'opencode run --model'"
echo "                          (e.g. ollama-cloud/minimax-m3). Empty = runner default."
echo "       BREW_TAP_ENABLED - 'true' to enable formula + bottle updates"
echo "       BREW_TAP_REPO    - owner/name of your Homebrew tap (e.g. you/homebrew-forge)"
echo "       MAIN_BRANCH / ISSUE_BRANCH_PREFIX - only set if your branch names differ"
echo "  3. Push to $DEV_BRANCH (or open a PR to $DEFAULT_BRANCH) to trigger the pipeline."
echo "     Open a bug/enhancement issue to trigger the level3 auto-fix path."
echo "  4. RUNNER REQUIREMENTS (set on the Forgejo runner host, not in the repo):"
echo "     - 'opencode' CLI on PATH (e.g. /var/home/<runner-user>/.opencode/bin/opencode)"
echo "     - 'opencode' configured with at least one provider/model"
echo "     - 'forgejo-actions' auto-token enabled (so \${{ github.token }} resolves)"
echo "     - 'jq' installed (used by triage / skip-notify jobs)"
echo "     - The runner must have a 'rust-ci' label registered pointing at"
echo "       ghcr.io/akinus21/rust-ci:latest (or your equivalent job image with"
echo "       rustc, cargo, opencode, jq pre-installed). The pipeline uses"
echo "       'runs-on: rust-ci' for that reason."