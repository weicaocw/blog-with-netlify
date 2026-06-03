#!/usr/bin/env bash
# publish.sh ["commit message"] — publish current blog changes:
#   sync render.R packages -> branch -> commit -> push -> open PR -> print preview URL
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MSG="${1:-Add/update blog post}"

# 1) keep render.R's package list in sync with what the posts use
command -v Rscript >/dev/null 2>&1 && Rscript "$SKILL_DIR/sync-packages.R" || true

# 2) site name (to compute the preview URL)
SITE_NAME="$(sed -nE 's/^[[:space:]]*site_name:[[:space:]]*"?([^"#]*)"?.*/\1/p' setup.config.yml 2>/dev/null | head -1)"

# 3) branch (create one if currently on main/master)
BR="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BR" = "main" ] || [ "$BR" = "master" ]; then
  BR="post/$(date +%Y%m%d-%H%M%S)"
  git checkout -b "$BR"
fi

# 4) commit + push
git add -A
if git diff --cached --quiet; then
  echo "(nothing to commit)"
else
  git commit -m "$MSG"
fi
git push -u origin "$BR"

# 5) open PR (or reuse existing)
gh pr view --json url -q .url >/dev/null 2>&1 || gh pr create --fill >/dev/null 2>&1 || true
PR_URL="$(gh pr view --json url -q .url 2>/dev/null || echo '')"
PR_NUM="$(gh pr view --json number -q .number 2>/dev/null || echo '')"

echo ""
echo "branch:  $BR"
echo "PR:      ${PR_URL:-<create failed; check gh>}"
if [ -n "$SITE_NAME" ] && [ -n "$PR_NUM" ]; then
  echo "preview: https://${PR_NUM}-merge--${SITE_NAME}.netlify.app  (live after CI; the bot also comments it on the PR)"
fi
