---
name: blog
description: Create, write, publish, and merge blog posts in this quarto + Netlify blog. Use when the user wants to start a new post, publish a post (open a PR with a Netlify preview), or merge a post live to production. Triggers on "/blog", "新建博客", "写一篇博客", "发布博客", "发布", "上线", "blog post".
---

# blog —— quarto + Netlify 博客发布

本仓库用 quarto 写博客、GitHub Actions 渲染、Netlify 部署（每个 PR 有预览，合并到 main 即上线正式站）。
本 skill 把日常发布自动化。辅助脚本在本 skill 目录：`new-post.sh`、`publish.sh`、`sync-packages.R`。
所有脚本都从仓库根目录运行。

根据用户意图执行下面三个动作之一。

## 1）新建文章（"新建/写一篇博客《标题》"或 `/blog new "标题"`）
- 运行：`bash .claude/skills/blog/new-post.sh "<标题>" [英文slug]`
  - 标题可中文；**slug 传一个简短英文**（如 `data-analysis`），它会成为网址的一部分。
- 脚本创建 `posts/<日期>-<slug>/index.qmd` 并填好 front matter，打印文件路径。
- 用 Read 打开该文件给用户看，告诉他："正文你来写；写好后说『发布』。"
- **不要替用户写正文**，除非他明确要求。

## 2）发布（"发布 / publish"）
- 先（可选）本地校验：`quarto render`（产物 `_site/` 已忽略）。失败就把错误拎给用户，先别发。
- 运行：`bash .claude/skills/blog/publish.sh "<简短提交信息>"`
  - 它会：扫描文章 `library()` 自动补 `render.R` 的包 → 建分支 → 提交 → 推送 → 开 PR → 打印 PR 和预览链接。
- 把 **PR 链接**和**预览链接**告诉用户。
- 主动提议盯 CI（用真实分支名替换 `<分支>`）：
  ```bash
  rid=$(gh run list --branch <分支> --limit 1 --json databaseId -q '.[0].databaseId')
  gh run watch "$rid" --exit-status
  ```
  跑完后 `curl -s -o /dev/null -w '%{http_code}' <预览URL>` 确认 200。
- 告诉用户："预览没问题就说『上线』，我来合并。"

## 3）上线（"上线 / 合并 / merge"）
- 找到对应 PR：`gh pr list`。
- **先确认用户已看过预览、满意**，再 `gh pr merge <PR#> --merge --delete-branch`。
- 合并到 main 触发正式部署。可 `gh run watch` 等 main 构建完成，再 `curl` 正式站
  `https://<site_name>.netlify.app` 确认 200。

## 注意
- push / 开 PR / 合并都是对外动作 —— **合并上线前务必让用户确认**。
- CI 失败时：`gh run view <id> --log-failed` 看日志（常见：文章代码报错、或缺系统库），把错误告诉用户。
- `<site_name>` 见 `setup.config.yml` 的 `netlify.site_name`。
