#!/usr/bin/env bash
###############################################################
# blog-with-netlify · setup 脚本
# 读取 setup.config.yml（无密钥）+ .env（密钥），一键完成：
#   脚手架博客 → render.R → workflow → 建 Netlify 站 → 存 secrets
#   → 本地渲染验证 → 推分支 + 开 PR（拿预览链接）
# 用法: ./setup.sh [配置文件路径，默认 setup.config.yml]
#   密钥放在 .env 文件（见 .env.example），或直接 export 到环境变量。
###############################################################
set -euo pipefail

info() { printf '\033[1;34m▶ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${1:-$DIR/setup.config.yml}"
ENV_FILE="${ENV_FILE:-$DIR/.env}"
TODAY="$(date +%Y-%m-%d)"

# ── 0. 前置检查 + 加载密钥 ────────────────────────────────
info "前置检查"
[ -f "$CONFIG" ] || die "找不到配置文件 $CONFIG"
for t in gh git curl jq quarto Rscript; do
  command -v "$t" >/dev/null 2>&1 || die "缺少工具: $t"
done
Rscript -e 'if(!requireNamespace("yaml",quietly=TRUE)) quit(status=1)' \
  || die "R 缺少 yaml 包: Rscript -e 'install.packages(\"yaml\")'"
gh auth status >/dev/null 2>&1 || die "GitHub 未登录: 先运行 gh auth login"
# 加载密钥文件 .env（每行 KEY=value；已被 .gitignore）
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi
ok "工具与登录态就绪"

# ── 1. 读取配置 ───────────────────────────────────────────
info "读取配置 $CONFIG"
CFG_VARS="$(Rscript "$DIR/read-config.R" "$CONFIG")" || die "解析配置失败"
eval "$CFG_VARS"

# Netlify token：来自 .env（NETLIFY_AUTH_TOKEN=...）或已 export 的同名环境变量
NETLIFY_TOKEN="${NETLIFY_AUTH_TOKEN:-}"
[ -n "$NETLIFY_TOKEN" ] \
  || die "未提供 Netlify 令牌：在 $ENV_FILE 写 NETLIFY_AUTH_TOKEN=...（参考 .env.example），或先 export NETLIFY_AUTH_TOKEN"
[ -n "$CFG_SITE_NAME" ] || die "缺少 netlify.site_name"
REPO="$CFG_GH_OWNER/$CFG_GH_REPO"
ok "仓库 $REPO · 站点 $CFG_SITE_NAME ($CFG_SITE_URL)"

# ── 2. 脚手架博客文件 ─────────────────────────────────────
if [ "$CFG_SCAFFOLD" = "TRUE" ]; then
  info "生成 quarto 博客脚手架"
  # 参考文档挪进 reference/，避免被当成博客页面发布
  mkdir -p reference
  for f in github_netlify.pdf github-netlify-workflow.md; do
    if [ -f "$f" ]; then git mv -k "$f" "reference/$f" 2>/dev/null || mv -f "$f" "reference/$f"; fi
  done

  cat > _quarto.yml <<EOF
project:
  type: website
  output-dir: $CFG_OUTPUT_DIR
  render:
    - index.qmd
    - about.qmd
    - posts/

website:
  title: "$CFG_SITE_TITLE"
  description: "$CFG_SITE_DESC"
  navbar:
    right:
      - about.qmd
      - icon: github
        href: https://github.com/$REPO

format:
  html:
    theme: cosmo
    css: styles.css

lang: $CFG_SITE_LANG
EOF

  cat > index.qmd <<EOF
---
title: "$CFG_SITE_TITLE"
listing:
  contents: posts
  sort: "date desc"
  type: default
  categories: true
  feed: true
page-layout: full
---
EOF

  cat > about.qmd <<EOF
---
title: "关于"
---

$CFG_SITE_DESC

作者：$CFG_SITE_AUTHOR
EOF

  printf '/* 自定义样式，按需编辑 */\n' > styles.css

  POST_DIR="posts/${TODAY}-hello-world"
  mkdir -p "$POST_DIR"
  # 前置信息（含变量）用普通 heredoc
  cat > "$POST_DIR/index.qmd" <<EOF
---
title: "Hello World"
author: "$CFG_SITE_AUTHOR"
date: "$TODAY"
categories: [R]
---
EOF
  # 正文（含反引号代码块）用引号 heredoc，避免被 shell 解释
  cat >> "$POST_DIR/index.qmd" <<'EOF'

这是第一篇博客 —— 用 R 打印一句问候，并把结果显示在页面上：

```{r}
print("hello world")
```
EOF
  ok "已生成 _quarto.yml / index.qmd / about.qmd / $POST_DIR/index.qmd"
else
  warn "scaffold=false，跳过脚手架（假定仓库已有博客源码）"
fi

# ── 3. 生成 render.R ──────────────────────────────────────
if [ "$CFG_R_ENABLED" = "TRUE" ]; then
  info "生成 render.R"
  PKGS="quarto $CFG_R_PACKAGES"           # quarto 包用于 quarto_render()
  R_VEC="$(printf '"%s", ' $PKGS | sed 's/, $//')"
  cat > render.R <<EOF
## render.R —— 由 setup 自动生成
## CI 在渲染前安装这些 R 包，然后渲染整个 quarto 站点。
## 以后新增 R 包：把名字加进 pkgs 向量，提交即可。
pkgs <- c($R_VEC)
installed <- rownames(installed.packages())
missing <- setdiff(pkgs, installed)
if (length(missing)) install.packages(missing)
EOF
  if [ -n "$CFG_R_EXTRA" ]; then
    echo 'Sys.setenv(NOT_CRAN = "true")' >> render.R
    for p in $CFG_R_EXTRA; do
      printf 'install.packages("%s", repos = "https://community.r-multiverse.org")\n' "$p" >> render.R
    done
  fi
  echo 'quarto::quarto_render()' >> render.R
  ok "render.R 包列表: $PKGS"
else
  warn "dependencies.r.enabled=false，不生成 render.R"
fi

# ── 4. 生成 GitHub Actions workflow ───────────────────────
info "生成 $CFG_WF_FILE"
mkdir -p "$(dirname "$CFG_WF_FILE")"
if [ "$CFG_WF_PRTOKEN" = "pat" ]; then
  PR_TOKEN='${{ secrets.PAT_GITHUB_PR }}'
else
  PR_TOKEN='${{ secrets.GITHUB_TOKEN }}'
fi
PY_STEPS=""
if [ "$CFG_PY_ENABLED" = "TRUE" ]; then
  PY_STEPS="
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: \"$CFG_PY_VERSION\"

      - name: Install Python packages
        run: pip install $CFG_PY_PACKAGES"
fi
cat > "$CFG_WF_FILE" <<EOF
name: build-site
on:
  push:
    branches: [$CFG_GH_BRANCH]
  pull_request:

permissions:
  contents: read
  pull-requests: write

jobs:
  build-site:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup R
        uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true

      - name: Setup Quarto
        uses: quarto-dev/quarto-actions/setup@v2
$PY_STEPS
      - name: Install R packages and render site
        run: Rscript render.R

      - name: Netlify deploy + PR comment
        uses: $CFG_WF_ACTION
        with:
          netlify_auth_token: \${{ secrets.NETLIFY_AUTH_TOKEN }}
          netlify_site_id:    \${{ secrets.NETLIFY_SITE_ID }}
          pat_github_pr:      $PR_TOKEN
          path:               $CFG_OUTPUT_DIR
          netlify_url:        $CFG_SITE_URL
EOF
ok "workflow 已生成（评论 token 模式: ${CFG_WF_PRTOKEN}）"

# ── 5. 本地渲染验证 ───────────────────────────────────────
info "本地渲染验证（quarto render）"
if quarto render >/tmp/blog-quarto-render.log 2>&1; then
  ok "本地渲染成功 → $CFG_OUTPUT_DIR/index.html（已被 .gitignore，不提交）"
else
  warn "本地渲染未通过，详见 /tmp/blog-quarto-render.log（不阻断，CI 会再渲染）"
fi

# ── 6. 创建 / 复用 Netlify 站点 ───────────────────────────
info "创建 / 查找 Netlify 站点 $CFG_SITE_NAME"
API="https://api.netlify.com/api/v1"
AUTH="Authorization: Bearer $NETLIFY_TOKEN"
EXISTING="$(curl -fsS -H "$AUTH" "$API/sites?name=$CFG_SITE_NAME" \
  | jq -r --arg n "$CFG_SITE_NAME" 'map(select(.name==$n))[0].id // empty' || true)"
if [ -n "$EXISTING" ]; then
  SITE_ID="$EXISTING"
  warn "已存在同名站点，复用 (id $SITE_ID)"
else
  if [ -n "$CFG_ACCOUNT_SLUG" ]; then
    BODY="{\"name\":\"$CFG_SITE_NAME\",\"account_slug\":\"$CFG_ACCOUNT_SLUG\"}"
  else
    BODY="{\"name\":\"$CFG_SITE_NAME\"}"
  fi
  RESP="$(curl -fsS -X POST -H "$AUTH" -H 'Content-Type: application/json' -d "$BODY" "$API/sites")" \
    || die "建站失败: 站点名 '$CFG_SITE_NAME' 可能已被占用，改 netlify.site_name 后重试"
  SITE_ID="$(echo "$RESP" | jq -r '.id')"
  ok "已创建 Netlify 站点 (id $SITE_ID)"
fi

# ── 7. 写入 GitHub secrets ────────────────────────────────
info "写入 GitHub secrets 到 $REPO"
printf '%s' "$NETLIFY_TOKEN" | gh secret set NETLIFY_AUTH_TOKEN -R "$REPO"
printf '%s' "$SITE_ID"       | gh secret set NETLIFY_SITE_ID    -R "$REPO"
ok "NETLIFY_AUTH_TOKEN / NETLIFY_SITE_ID 已写入"
# pat 模式：若 .env 提供了 PAT_GITHUB_PR，一并写入（用于 fork PR 的预览评论）
if [ "$CFG_WF_PRTOKEN" = "pat" ] && [ -n "${PAT_GITHUB_PR:-}" ]; then
  printf '%s' "$PAT_GITHUB_PR" | gh secret set PAT_GITHUB_PR -R "$REPO"
  ok "PAT_GITHUB_PR 已写入"
elif [ "$CFG_WF_PRTOKEN" = "pat" ]; then
  warn "pr_comment_token=pat 但 .env 未提供 PAT_GITHUB_PR，跳过（fork PR 预览评论将失效）"
fi

# ── 8. 提交并开 PR ────────────────────────────────────────
info "提交源文件并推送分支 $CFG_WF_BRANCH"
git checkout -b "$CFG_WF_BRANCH" 2>/dev/null || git checkout "$CFG_WF_BRANCH"
git add -A
git commit -m "Set up Netlify deploy workflow + first hello-world post" \
  || warn "没有可提交的改动"
git push -u origin "$CFG_WF_BRANCH"

info "创建 Pull Request"
PR_URL="$(gh pr create -R "$REPO" --base "$CFG_GH_BRANCH" --head "$CFG_WF_BRANCH" \
  --title "Set up Netlify deploy + first post" \
  --body "由 setup.sh 自动配置：quarto 博客脚手架、build-site.yml、render.R、首篇 hello-world。CI 跑完后机器人会在本 PR 评论预览链接；合并后正式站上线。" 2>&1)" \
  || PR_URL="$(gh pr view --json url -q .url 2>/dev/null || echo '(PR 可能已存在，请到 GitHub 查看)')"
ok "PR: $PR_URL"

# ── 9. 总结 ───────────────────────────────────────────────
cat <<EOF

══════════════════════════════════════════════════════
✅ Setup 完成

  仓库:    https://github.com/$REPO
  PR:      $PR_URL
  预览:    CI 构建完成后，机器人会在 PR 里评论
           https://<PR号>-merge--$CFG_SITE_NAME.netlify.app
  正式站:  合并 PR 后生效 → https://$CFG_SITE_URL

下一步:
  1) 打开上面的 PR，等绿色对勾（CI 完成）
  2) 点机器人评论里的 Preview，看 hello-world 页面
  3) 满意就 Merge → 正式站自动上线
══════════════════════════════════════════════════════
EOF
