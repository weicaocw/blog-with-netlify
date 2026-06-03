#!/usr/bin/env Rscript
## read-config.R —— 读取 setup.config.yml，输出 shell 变量赋值（供 setup.sh eval）
## 注意：本文件不含密钥；密钥由 setup.sh 从 env 文件加载。
## 用法: Rscript read-config.R setup.config.yml
suppressWarnings(suppressMessages(library(yaml)))

args <- commandArgs(trailingOnly = TRUE)
cfg_file <- if (length(args) >= 1) args[1] else "setup.config.yml"
if (!file.exists(cfg_file)) {
  message(sprintf("找不到配置文件: %s", cfg_file)); quit(status = 1)
}
y <- yaml::read_yaml(cfg_file)

## 按路径取值，缺失返回 ""
g <- function(...) {
  v <- y
  for (k in c(...)) {
    if (is.null(v) || is.null(v[[k]])) return("")
    v <- v[[k]]
  }
  if (is.null(v)) "" else v
}
## 安全单引号转义，数组用空格连接
shq <- function(x) {
  x <- paste(as.character(x), collapse = " ")
  paste0("'", gsub("'", "'\\''", x, fixed = TRUE), "'")
}
emit <- function(name, ...) cat(sprintf("%s=%s\n", name, shq(g(...))))

emit("CFG_GH_OWNER",      "github", "owner")
emit("CFG_GH_REPO",       "github", "repo")
emit("CFG_GH_VIS",        "github", "visibility")
emit("CFG_GH_BRANCH",     "github", "default_branch")
emit("CFG_GH_PROTO",      "github", "remote_protocol")
emit("CFG_SITE_NAME",     "netlify", "site_name")
emit("CFG_SITE_URL",      "netlify", "url")
emit("CFG_ACCOUNT_SLUG",  "netlify", "account_slug")
emit("CFG_GEN_TYPE",      "generator", "type")
emit("CFG_OUTPUT_DIR",    "generator", "output_dir")
emit("CFG_SCAFFOLD",      "generator", "scaffold")
emit("CFG_SITE_TITLE",    "site", "title")
emit("CFG_SITE_DESC",     "site", "description")
emit("CFG_SITE_AUTHOR",   "site", "author")
emit("CFG_SITE_EMAIL",    "site", "email")
emit("CFG_SITE_LANG",     "site", "language")
emit("CFG_WF_FILE",       "workflow", "file")
emit("CFG_WF_BRANCH",     "workflow", "setup_branch")
emit("CFG_WF_ACTION",     "workflow", "deploy_action")
emit("CFG_WF_PRTOKEN",    "workflow", "pr_comment_token")
emit("CFG_R_ENABLED",     "dependencies", "r", "enabled")
emit("CFG_R_PACKAGES",    "dependencies", "r", "packages")
emit("CFG_R_EXTRA",       "dependencies", "r", "extra_packages")
emit("CFG_PY_ENABLED",    "dependencies", "python", "enabled")
emit("CFG_PY_VERSION",    "dependencies", "python", "version")
emit("CFG_PY_PACKAGES",   "dependencies", "python", "packages")
