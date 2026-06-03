#!/usr/bin/env Rscript
## Scan blog .qmd files for R packages used (library/require/pkg::) and add any
## missing ones to render.R's pkgs vector. Prints what was added.
setwd(system("git rev-parse --show-toplevel", intern = TRUE))
if (!file.exists("render.R")) { cat("(no render.R, skipping)\n"); quit() }

qmds <- list.files(".", pattern = "\\.qmd$", recursive = TRUE, full.names = TRUE)
if (!length(qmds)) quit()
txt <- unlist(lapply(qmds, readLines, warn = FALSE))

libs <- gsub("^(?:library|require)\\(|\\)$", "",
  unlist(regmatches(txt, gregexpr("(?:library|require)\\([A-Za-z][A-Za-z0-9.]*\\)", txt, perl = TRUE))),
  perl = TRUE)
cc <- unlist(regmatches(txt, gregexpr("[A-Za-z][A-Za-z0-9.]*(?=::)", txt, perl = TRUE)))
found <- unique(c(libs, cc))
base_pkgs <- c("base","stats","utils","methods","graphics","grDevices","datasets","tools")
found <- setdiff(found, c("", base_pkgs))

src <- paste(readLines("render.R"), collapse = "\n")
mt <- regmatches(src, regexpr("pkgs <- c\\([^)]*\\)", src))
if (!length(mt)) { cat("(no pkgs vector in render.R, skipping)\n"); quit() }
cur <- gsub('"', '', unlist(regmatches(mt, gregexpr('"[^"]+"', mt))))

missing <- setdiff(found, cur)
if (!length(missing)) { cat("render.R already lists every package used.\n"); quit() }

newvec <- paste0('pkgs <- c(', paste0('"', unique(c(cur, missing)), '"', collapse = ", "), ')')
writeLines(sub("pkgs <- c\\([^)]*\\)", newvec, src), "render.R")
cat("Added to render.R:", paste(missing, collapse = ", "), "\n")
