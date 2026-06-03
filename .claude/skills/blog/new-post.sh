#!/usr/bin/env bash
# new-post.sh "<title>" [slug] — scaffold a new blog post under posts/
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

TITLE="${1:?usage: new-post.sh \"title\" [slug]}"
TODAY="$(date +%Y-%m-%d)"
AUTO="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-' | sed 's/^-//; s/-$//')"
SLUG="${2:-$AUTO}"
[ -n "$SLUG" ] || SLUG="post-$(date +%H%M%S)"
DIR="posts/${TODAY}-${SLUG}"
[ -d "$DIR" ] && { echo "already exists: $DIR" >&2; exit 1; }
mkdir -p "$DIR"

# default author from setup.config.yml (site.author)
AUTHOR="$(sed -nE 's/^[[:space:]]*author:[[:space:]]*"?([^"#]*)"?.*/\1/p' setup.config.yml 2>/dev/null | head -1)"
[ -n "$AUTHOR" ] || AUTHOR="Author"

cat > "$DIR/index.qmd" <<EOF
---
title: "$TITLE"
author: "$AUTHOR"
date: "$TODAY"
categories: []
---
EOF
cat >> "$DIR/index.qmd" <<'EOF'

Write your post here. You can embed executable code, e.g.:

```{r}
summary(cars)
```
EOF

echo "$DIR/index.qmd"
