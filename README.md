# blog-with-netlify

用 **GitHub + Netlify** 搭建的协作式个人博客：仓库里**只放源码**（`.qmd` + R/Python 代码），
网页由 **GitHub Actions 在云端渲染**并部署到 **Netlify**；每个 PR 自动生成**预览站**，
合并后**正式站自动更新**。

> 工作流出处与逐页分析见 [`reference/github_netlify.pdf`](reference/github_netlify.pdf) 与
> [`reference/github-netlify-workflow.md`](reference/github-netlify-workflow.md)
> （运行 `setup.sh` 后这两份文档会被移到 `reference/`）。

---

## 目录
- [核心理念](#核心理念)
- [整体工作流](#整体工作流)
- [密钥与配置的分工](#密钥与配置的分工)
- [仓库结构](#仓库结构)
- [前置条件](#前置条件)
- [一次性配置（setup.sh）](#一次性配置setupsh)
- [配置文件逐项说明](#配置文件逐项说明)
- [日常写作：发布一篇新博客](#日常写作发布一篇新博客)
- [以后新增 R / Python 包](#以后新增-r--python-包)
- [进阶：接受 fork 贡献时改用 PAT_GITHUB_PR](#进阶接受-fork-贡献时改用-pat_github_pr)
- [安全须知](#安全须知)
- [常见问题](#常见问题)

---

## 核心理念

分离的不是「内容 vs 代码」，而是 **源码 vs 生成的网页**：

| 类别 | 例子 | 进 Git 仓库？ |
|---|---|---|
| **源码** | `.qmd`（文字 + R/Python 代码块）、`_quarto.yml`、`styles.css`、图片 | ✅ 进 |
| **你文章里的代码** | `library()`、`print("hello world")` …（属于源码，是输入） | ✅ 进 |
| **生成产物** | `_site/` 里渲染出的 `.html`、拷贝的资源（机器产出） | ❌ 不进（`.gitignore`） |

> 类比：提交 `.c` 源文件，不提交编译出的 `.exe`。这里提交 `.qmd`，不提交渲染出的 `.html`。

相比 GitHub Pages：Pages **要求把生成的 HTML 也塞进仓库**（臃肿、慢）且**没有 per-PR 预览**；
Netlify 让仓库**只留源码**（干净、快）且**每个 PR 都有独立预览**。

---

## 整体工作流

```
                       ┌─────────── 一次性配置（setup.sh，每仓库一次）───────────┐
                       │ 建 Netlify 站 · 存 secrets · 生成 workflow+render.R · 开首个 PR │
                       └────────────────────────────────────────────────────────┘

  ─────────────────────── 日常循环（每篇博客）───────────────────────
   写 .qmd ──push──▶ PR ──▶ GitHub Actions VM
                              │ （setup R + quarto，跑 render.R：装包 + 渲染）
                              ▼
                         _site/ 生成
                              │
                              ▼
                      Netlify 草稿部署（预览站）
                              │
                              ▼
                机器人在 PR 评论 Preview 链接（带 pull-requests:write 的 token）
                              │
                 审阅 diff + 点预览 ──▶ Merge ──▶ 正式站更新
```

---

## 密钥与配置的分工

| 文件 | 内容 | 是否提交 git |
|---|---|---|
| `setup.config.yml` | **所有非密钥配置**（仓库、站点名、依赖…） | ✅ 提交（方便复现） |
| `.env` | **密钥**：`NETLIFY_AUTH_TOKEN=…`、可选 `PAT_GITHUB_PR=…` | ❌ **绝不提交**（`.gitignore`） |
| `.env.example` | `.env` 的占位模板 | ✅ 提交 |

> 设计原则：**配置可公开、密钥单独藏**。`setup.sh` 会读 `setup.config.yml` 拿配置、
> 加载 `.env` 拿密钥（也支持直接用 `export NETLIFY_AUTH_TOKEN=...` 环境变量）。

---

## 仓库结构

`setup.sh` 运行后，仓库大致如下：

```
blog-with-netlify/
├─ _quarto.yml                 # 站点级配置（标题/导航/主题），来自 setup.config.yml 的 site.*
├─ index.qmd                   # 博客首页（文章列表）
├─ about.qmd                   # 关于页
├─ styles.css                  # 自定义样式
├─ render.R                    # CI 渲染脚本：装 R 包 + quarto::quarto_render()
├─ posts/
│   └─ 2026-06-03-hello-world/
│       └─ index.qmd           # 第一篇博客（R 打印 hello world）
├─ .github/workflows/build-site.yml   # GitHub Actions：渲染 + 部署 + 评论
├─ setup.sh                    # 一次性配置脚本
├─ read-config.R              # setup.sh 的 YAML 解析器
├─ setup.config.yml            # 配置（无密钥，可提交）
├─ .env.example                 # 密钥文件模板（可提交）
├─ .env                         # 真实密钥（NETLIFY_AUTH_TOKEN=…，已 .gitignore）  ← 你创建
├─ reference/                  # 原讲座 PDF 与分析（不发布）
├─ _site/                      # 生成的网页（.gitignore，不提交）
└─ .gitignore
```

---

## 前置条件

本机需要（已确认你都装好了）：

| 工具 | 用途 | 检查 |
|---|---|---|
| `git` + `gh`（已登录） | 建/推仓库、存 secret、开 PR | `gh auth status` |
| `quarto` | 渲染博客 | `quarto --version` |
| `R`（含 `yaml`/`knitr`/`rmarkdown`/`quarto` 包） | 解析配置 + 本地渲染 | `Rscript -e 'library(yaml)'` |
| `curl` + `jq` | 调 Netlify API 建站 | `jq --version` |

另需一个 **Netlify 账号**（免费，可用 GitHub 登录注册）。

---

## 一次性配置（setup.sh）

### 快速开始（4 步）

```bash
# 1) 申请 Netlify 令牌（见下方手把手）

# 2) 复制密钥模板，填入令牌
cp .env.example .env
$EDITOR .env                       # 填 NETLIFY_AUTH_TOKEN=你的令牌

# 3)（按需）改 setup.config.yml 里的 site_name 等（无密钥，可直接提交）

# 4) 运行
./setup.sh

# 5) 打开脚本输出的 PR → 等绿勾 → 点 Preview 看 hello-world → Merge 上线
```

### 手把手：申请 Netlify 令牌（唯一必须手动拿的密钥）

1. 打开 <https://app.netlify.com/user/applications/personal>
   （没账号？点 **Sign up**，用你的 GitHub 登录即可，免费）
2. 点 **New access token**
3. Description 填 `blog-with-netlify`
4. Expiration 选 **No expiration**
5. 点 **Generate token** → **立刻复制**（只显示这一次）
6. 写进 `.env` 文件：`NETLIFY_AUTH_TOKEN=你复制的令牌`
   （`.env` 已 .gitignore，不会提交；也可改用 `export NETLIFY_AUTH_TOKEN=...` 环境变量）

> GitHub 这边**不用申请任何东西**——你已 `gh auth login`，且 token 自带 `repo`+`workflow` 权限。

### setup.sh 会自动做的事（按顺序）

1. **前置检查 + 加载 .env**：工具齐全、GitHub 已登录、`.env` 里有 Netlify 令牌。
2. **脚手架博客**：把参考文档归入 `reference/`，生成 `_quarto.yml`、`index.qmd`、
   `about.qmd`、`styles.css`、`posts/<日期>-hello-world/index.qmd`。
3. **生成 `render.R`**：CI 装包清单 = `quarto` + 你配置的 R 包。
4. **生成 `build-site.yml`**：GitHub Actions 工作流（含部署 + 评论步骤）。
5. **本地渲染验证**：`quarto render` 跑一遍，提前发现错误（产物 `_site/` 不提交）。
6. **建 Netlify 站点**：调 API 创建（或复用同名站），拿到 **Site ID**。
7. **写 GitHub secrets**：`NETLIFY_AUTH_TOKEN`、`NETLIFY_SITE_ID`（pat 模式还会写 `PAT_GITHUB_PR`）。
8. **开 PR**：建 `add-netlify` 分支、提交源文件、推送、`gh pr create`。
9. **打印总结**：PR 链接、预览地址规则、正式站地址。

脚本**幂等**：重复运行会复用已建的站、覆盖 secrets、重新生成文件，安全。
它**只开 PR，不自动合并**——上线与否由你点 Merge 决定。

---

## 配置文件逐项说明

`setup.config.yml`（无密钥，可提交）。**密钥不在这里，在 `.env` 文件**（见上方表格）。

### `github`（仓库）
| 字段 | 说明 | 你的值 |
|---|---|---|
| `owner` | GitHub 登录名（非本地 git 提交名） | `weicaocw` |
| `repo` | 仓库名 | `blog-with-netlify` |
| `visibility` | `public` / `private` | `public` |
| `default_branch` | 主分支 | `main` |
| `remote_protocol` | `ssh` / `https` | `ssh` |

### `netlify`（站点）
| 字段 | 说明 |
|---|---|
| `site_name` | = 项目名 = 网址前缀，**Netlify 全局唯一**（被占用则脚本报错，换名重试） |
| `url` | 站点网址，须 = `site_name` + `.netlify.app` |
| `account_slug` | 留空=默认团队；多团队时填团队 slug |

### `generator`（生成器）
| 字段 | 说明 |
|---|---|
| `type` | `quarto`（博客）/ `litedown` / `pkgdown`（R 包文档） |
| `output_dir` | 含 `index.html` 的输出目录，写进 workflow 的 `path`（quarto 博客默认 `_site`） |
| `scaffold` | `true`=用模板新建博客；`false`=仓库已有源码，不新建 |

### `site`（站点元信息，写进 `_quarto.yml`，**站点级、一次性**）
| 字段 | 说明 |
|---|---|
| `title` | 站点标题（顶栏显示） |
| `description` | 站点简介 |
| `author` | 默认作者 |
| `email` / `language` | 联系邮箱 / 站点语言（如 `zh`） |

> ⚠️ 这些是**整个站点**的信息，不是单篇文章。每篇博文的标题/日期/分类写在**该文 `index.qmd` 的 front matter** 里，不在这里。

### `workflow`（CI）
| 字段 | 说明 |
|---|---|
| `file` | 工作流文件路径 |
| `setup_branch` | setup 时新建的分支名（默认 `add-netlify`） |
| `deploy_action` | 部署+评论用的 Action |
| `pr_comment_token` | `personal`=用自动 `GITHUB_TOKEN`（个人博客）/ `pat`=用 `PAT_GITHUB_PR`（见进阶节） |

### `dependencies`（多语言依赖，CI 虚拟机里装什么）
| 字段 | 说明 |
|---|---|
| `r.enabled` | 写 R 文章就 `true` → 生成 `render.R` |
| `r.packages` | CI 要装的 R 包（你文章会 `library()` 的） |
| `r.extra_packages` | 额外源的包（如 `polars` from r-multiverse），没有留 `[]` |
| `python.enabled` | 以后写 Python 文章改 `true` → workflow 自动加 `setup-python` + `pip install` |
| `python.version` / `python.packages` | Python 版本与要装的库 |

---

## 日常写作：发布一篇新博客

> 「写完内容 → 怎么操作 → 自动发生什么」。两种方式：**手动（现在可用）** 与 **skill（规划中）**。

### 方式 A · 手动（现在就能用）

```bash
# 1) 开分支
git checkout -b post/my-topic

# 2) 新建文章目录与文件
mkdir -p posts/$(date +%Y-%m-%d)-my-topic
$EDITOR posts/$(date +%Y-%m-%d)-my-topic/index.qmd
```

`index.qmd` 内容示例：

````markdown
---
title: "我的文章标题"
author: "Caowei"
date: "2026-06-03"
categories: [R]
---

正文……

```{r}
summary(cars)
```
````

```bash
# 3) （可选）本地预览，确认无误
quarto preview                 # 浏览器实时预览；或 quarto render 渲染一次

# 4) 若用到新包，把包名加进 render.R 的 pkgs 向量（见下一节）

# 5) 提交、推送、开 PR
git add -A
git commit -m "新增文章：我的文章标题"
git push -u origin post/my-topic
gh pr create --fill

# 6) 等 PR 里 CI 绿勾 → 点机器人评论的 Preview 看效果
# 7) 满意 → Merge → 正式站自动更新
```

**你只需专注第 2 步写内容**；分支/CI/预览/部署都是机械步骤。

### 方式 B · 自动化 skill（规划中，尚未实现）

计划用 `skill-creator` 做一个 `/blog` skill，把方式 A 的机械步骤一键化：

| 命令 | 自动做什么 |
|---|---|
| `/blog new "标题"` | 建好 `posts/<日期>-slug/index.qmd` 并填好 front matter |
| ✍️ 你写内容 | （唯一需要你做的事） |
| `/blog publish` | 本地渲染校验 → **扫描文章 `library()` 自动补 `render.R`** → 建分支/commit/push/开 PR → 等 CI → 取预览链接 → 在 PR 评论**每个改动页面**的直达链接 |
| `/blog merge` | 合并 PR → 正式站上线 → 回报正式网址 |

> 这正好实现了讲座留下的两个「future work」：自动链接所有改动页面、`render.R` 自动判定要装的包。
> 该 skill 目前**未实现**；需要时告诉我，用 `skill-creator` 创建。

---

## 以后新增 R / Python 包

**关键认知**：`setup.config.yml` 的依赖列表只在 setup 那一次用到；之后「CI 装哪些包」的真身在仓库的
**`render.R`**（R）和 **`build-site.yml`**（Python）里。

### 新增 R 包（手动）
编辑 `render.R`，把包名加进 `pkgs` 向量：
```r
pkgs <- c("quarto", "knitr", "rmarkdown",
          "dplyr")        # ← 新增
```
非 CRAN 源的包加到那段特殊安装（脚本已预留）：
```r
install.packages("polars", repos = "https://community.r-multiverse.org")
```
提交并推送，下次 PR 构建就会装上。（将来 `/blog publish` 可自动维护这份清单。）

### 启用 Python 博文
编辑 `setup.config.yml`：
```yaml
dependencies:
  python:
    enabled: true
    version: "3.12"
    packages: [jupyter, pandas, matplotlib]
```
重新跑 `./setup.sh`，它会在 `build-site.yml` 自动加上 `setup-python` 与 `pip install` 步骤。
之后 `.qmd` 里直接写 ` ```{python} ` 代码块即可（同一博客可 R、Python 文章混用）。

---

## 进阶：接受 fork 贡献时改用 PAT_GITHUB_PR

### 先理解两种「评论令牌」

CI 部署完预览后，要在 PR 上**自动贴一条 Preview 链接评论**；贴评论需要一个带
`pull-requests: write` 权限的令牌。两种来源：

| 方案 | 来源 | 适用 | 代价 |
|---|---|---|---|
| **`personal`（默认）** | GitHub 每次运行**自动注入**的 `GITHUB_TOKEN` | 你/协作者在**本仓库**开分支提 PR | 零配置、不过期、更安全 |
| **`pat`** | 你**手动建**的 `PAT_GITHUB_PR`（长期令牌，放 `.env`） | 接受**外部 fork** 的 PR | 需手动建、会过期 |

### 什么时候需要 `pat`？

当你开始接受**外部贡献者从他们 fork 的仓库**提 PR（他们没有本仓库 push 权限）。出于安全，
GitHub 对 **fork 发起的 PR**：

- 把自动的 `GITHUB_TOKEN` 降为**只读** → 贴不了评论；
- 且**默认不把仓库 secrets 传给 fork PR 触发的运行**。

> 个人博客（只有你自己写）**用不到这一节**，保持默认 `personal` 即可。

### 脚本已内置支持，切到 pat 模式只需 3 步

> 改造已经做好：`setup.sh` 会从 `.env` 读 `PAT_GITHUB_PR`，并在 `pr_comment_token: pat`
> 时自动把它写成 GitHub secret。你**不用再改脚本**，按下面填值即可。

**① 申请 PAT（GitHub 无 API，只能手动一次）**
1. 打开 <https://github.com/settings/personal-access-tokens/new>
2. Token name：`blog-with-netlify PR comment`
3. Resource owner：选你自己（`weicaocw`）
4. Expiration：自定（到期需重建）
5. Repository access：**Only select repositories** → 勾 `weicaocw/blog-with-netlify`
6. Permissions → Repository permissions → **Pull requests: Read and write**
7. **Generate token** → 复制（只显示一次）

**② 把它写进 `.env`**（和 Netlify 令牌同一个文件，已 .gitignore）：
```ini
NETLIFY_AUTH_TOKEN=nfp_...
PAT_GITHUB_PR=github_pat_...
```

**③ 把配置切到 pat 模式并重跑**
```yaml
# setup.config.yml
workflow:
  pr_comment_token: "pat"     # personal → pat
```
```bash
./setup.sh
# 脚本会：重新生成 build-site.yml（评论令牌引用变为 ${{ secrets.PAT_GITHUB_PR }}）
#         并把 .env 里的 PAT_GITHUB_PR 写成仓库 secret
```

**④（仅 fork PR 需要）让构建能拿到 secrets**
把 `.github/workflows/build-site.yml` 的触发从 `pull_request` 改为 `pull_request_target`。
⚠️ 它在**基仓库**上下文运行、能访问 secrets，但因此会执行/检出**不受信任的 fork 代码**，
存在安全风险，务必参考
[GitHub 官方文档](https://securitylab.github.com/resources/github-actions-preventing-pwn-requests/)
谨慎处理。**同仓库分支 PR 不需要这步。**

### 背后脚本是怎么支持的（参考）

`setup.sh` 第 4 步（生成 workflow）已按模式切换评论令牌引用：
```bash
if [ "$CFG_WF_PRTOKEN" = "pat" ]; then
  PR_TOKEN='${{ secrets.PAT_GITHUB_PR }}'
else
  PR_TOKEN='${{ secrets.GITHUB_TOKEN }}'
fi
```
第 7 步（写 secrets）在 pat 模式下自动写入 PAT（值来自 `.env`）：
```bash
if [ "$CFG_WF_PRTOKEN" = "pat" ] && [ -n "${PAT_GITHUB_PR:-}" ]; then
  printf '%s' "$PAT_GITHUB_PR" | gh secret set PAT_GITHUB_PR -R "$REPO"
fi
```

---

## 安全须知

- **密钥只在 `.env` 文件**（`NETLIFY_AUTH_TOKEN=…`、可选 `PAT_GITHUB_PR=…`），已在 `.gitignore`，**绝不提交**。
- `setup.config.yml`（无密钥）**可以提交**，方便复现配置；分享前确认里面没误填令牌。
- 也可不建 `.env`，直接 `export NETLIFY_AUTH_TOKEN=...`（及 `PAT_GITHUB_PR=...`）；脚本两者都认。
- `_site/`、`.quarto/` 是生成产物，已忽略，**永不入库**。

---

## 常见问题

**Q：本地渲染失败但我想继续？**
脚本里本地渲染是**非阻断**的（失败只警告，日志在 `/tmp/blog-quarto-render.log`），CI 会再渲染一次。

**Q：站点名被占用？**
`netlify.site_name` 是 Netlify 全局唯一的。脚本建站报错时，改个更独特的名字（同时改 `url`）再跑。

**Q：正式站什么时候更新？**
合并 `add-netlify`（或任何）PR 到 `main` 后，Actions 在 `main` 上构建并部署到正式站。
合并前，PR 的预览站是独立的 `https://<PR号>-merge--<site>.netlify.app`。

**Q：原讲座的完整流程/分析在哪？**
见 `reference/github_netlify.pdf` 与 `reference/github-netlify-workflow.md`。
