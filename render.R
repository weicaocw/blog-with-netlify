## render.R —— 由 setup 自动生成
## CI 在渲染前安装这些 R 包，然后渲染整个 quarto 站点。
## 以后新增 R 包：把名字加进 pkgs 向量，提交即可。
pkgs <- c("quarto", "knitr", "rmarkdown")
installed <- rownames(installed.packages())
missing <- setdiff(pkgs, installed)
if (length(missing)) install.packages(missing)
quarto::quarto_render()
