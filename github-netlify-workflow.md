# Collaborative web sites with GitHub + Netlify

> Workflow extracted from Toby Dylan Hocking's talk *"Collaborative web sites with
> GitHub+Netlify"* (`toby.hocking@r-project.org`, CC-BY), plus an analysis of how
> much of it can be automated.

## The idea in one paragraph

Keep **only source** in a GitHub repo (`.qmd` / R package code — never the generated
HTML). On every Pull Request, GitHub Actions spins up a VM, executes your code
chunks, and renders the site (quarto for blogs; litedown/pkgdown for R package docs).
The rendered site is pushed to **Netlify**, which publishes a **per-PR preview** at a
throwaway URL without touching the main site. A bot comments the preview link on the
PR. Reviewers read the source diff *and* click through the live preview; **merging the
PR updates the production site**. This is the GitHub-Pages experience minus its two
pain points: no generated files bloating the repo, and a real preview per PR.

```
 edit .qmd / R code  ──push──▶  PR  ──▶  GitHub Actions VM
                                          │  (quarto/litedown runs your R/Python,
                                          │   produces _site/index.html)
                                          ▼
                                       Netlify draft deploy
                                          │
                                          ▼
                            bot comments "Preview" link on PR
                                          │
                            review source + live preview
                                          │
                                       merge PR
                                          ▼
                                  production site updates
```

---

## Part 1 — One-time setup (per repository)

The canonical ordered checklist (talk's "Overview of setup steps"), with the concrete
commands/links from each slide.

### 0. Prerequisites
- A GitHub account and a Netlify account (free tiers are fine).
- Local R with `quarto` (for blogs) or `litedown` / `pkgdown` (for R package docs).
- `git`, and ideally the `gh` CLI.

### 1. Create / clone the source repo
- Existing R package → just clone it.
- New blog/package → scaffold and push:

```r
quarto::quarto_create_project("YOUR_REPO", "blog")
```
```bash
cd YOUR_REPO
git init
echo _site > .gitignore && echo .quarto >> .gitignore   # NEVER commit generated site
git add *yml *qmd *jpg *css posts/ .gitignore
git commit -am "first commit from quarto blog template"
# Windows:
git remote add origin https://github.com/YOUR_USER/YOUR_REPO
# Ubuntu/SSH:
git remote add origin git@github.com:YOUR_USER/YOUR_REPO
git push -u origin main
```
(Create the empty GitHub repo first via the **+ ▸ New repository** menu, or `gh repo create`.)

### 2. Build the site locally once
```r
litedown::fuse_site("site")        # litedown
quarto::quarto_render("YOUR_REPO") # quarto
```
This produces `index.html` in a `site/`, `_site/`, or `docs/` folder.
**Add that folder to `.gitignore`. Do not commit generated site files.**

### 3. Create the Netlify project
Drag the generated folder onto **Upload your project files** at
<https://app.netlify.com/start>. This creates a new Netlify project from the build.

### 4. Define the project name (URL) and note the Site ID
In Netlify ▸ **Project configuration ▸ General**:
1. **Note the Project ID** (a.k.a. **Site ID**, a UUID) — you'll store it as a GitHub secret.
2. **Change project name** — the name becomes your URL: `YOUR-SITE-NAME.netlify.app`.

### 5. Generate a Netlify token
At <https://app.netlify.com/user/applications/personal>:
- Name it (e.g. same as the site), **Expiration: No expiration**, **Generate token**.
- It is shown **once** — copy it now; you'll paste it as a GitHub secret.

### 6. Store Netlify credentials as GitHub secrets
Repo ▸ **Settings ▸ Secrets and variables ▸ Actions**
(`https://github.com/YOUR_USER/YOUR_REPO/settings/secrets/actions`) → **New repository secret**:

| Secret name | Value |
|---|---|
| `NETLIFY_AUTH_TOKEN` | the token from step 5 |
| `NETLIFY_SITE_ID` | the Site ID from step 4 |

### 7. (Talk's approach) Set up the automatic PR-comment token
To let the Action post the "Preview" link as a PR comment, the talk creates a GitHub PAT:
- <https://github.com/settings/personal-access-tokens/new>
- **Resource owner** = the org/user, **Repository access** = *Only select repositories* → your repo
- **Permissions ▸ Pull requests** = *Read and write*, **Generate token**, copy it
- Store it as repo secret **`PAT_GITHUB_PR`**.

> 💡 This step is **avoidable** — see Part 3. The built-in `GITHUB_TOKEN` can post the
> comment for same-repo PRs with zero manual token creation.

### 8. Add the GitHub Actions workflow
`git checkout -b add-netlify`, then create `.github/workflows/build-site.yml`.
Reference workflows from the talk:

| Generator | Example workflow |
|---|---|
| Simple litedown | `tdhock/atime/.github/workflows/build-docs.yaml` |
| Complex litedown (installs SLURM + torch) | `tdhock/mlr3resampling/.github/workflows/build-docs.yaml` |
| Simple quarto | `rdatatable-community/data-table-raft/.github/workflows/build-site.yml` |
| Complex quarto | `animint/animint-manual-en/.github/workflows/build-book.yml` |

The deploy step (the part you edit — `path` is the folder containing `index.html`):

```yaml
- name: netlify deploy
  uses: animint/animint-actions/netlify-deploy-comment@main
  with:
    netlify_auth_token: ${{ secrets.NETLIFY_AUTH_TOKEN }}
    netlify_site_id:    ${{ secrets.NETLIFY_SITE_ID }}
    pat_github_pr:      ${{ secrets.PAT_GITHUB_PR }}
    path:               _site
    netlify_url:        YOUR-SITE-NAME.netlify.app
```

### 9. (quarto only) Add `render.R` to install R packages in the VM
quarto needs the R packages available in the Actions VM. The talk proposes a `render.R`
(example: `rdatatable-community/data-table-raft/render.R`):

```r
pkgs <- c("mlr3verse","fastverse","ranger","tidyfast","dtplyr","data.table",
  "magrittr", "palmerpenguins", "tidyverse", "knitr", "dplyr", "reshape2",
  "atime", "ggplot2", "reticulate", "quarto", "kknn", "nc", "duckdb",
  "directlabels")
ins.mat <- installed.packages()
missing.pkgs <- setdiff(pkgs, rownames(ins.mat))
install.packages(missing.pkgs)
Sys.setenv(NOT_CRAN = "true") # https://pola-rs.github.io/r-polars/
install.packages("polars", repos = "https://community.r-multiverse.org")
unlink("docs", recursive = TRUE)
quarto::quarto_render()
```
(For *this* blog, replace the package list with what your posts actually `library()` —
e.g. `mlr3torch`, `aum`, `torch`, ….)

### 10. Commit, push, verify
- Commit **only** the new workflow + `render.R` (not generated site files), then `git push`.
- Confirm three secrets exist: `NETLIFY_AUTH_TOKEN`, `NETLIFY_SITE_ID`, `PAT_GITHUB_PR`
  (or two, if you used the `GITHUB_TOKEN` shortcut).
- Open the PR, wait for Actions, click **Details** on the green check. Under the
  **netlify deploy** step you should see `Draft deploy is live → Deployed draft to
  https://<branch>--YOUR-SITE-NAME.netlify.app`.

### 11. Link the changed pages in the PR
The bot auto-comments a **Preview** link to `index.html`. Manually add links to the
specific pages you added/changed so reviewers land on them directly.

---

## Part 2 — The everyday loop (the payoff)

Once set up, every contribution is:

1. One person branches, edits `.qmd`/R code, pushes, opens a **PR**.
2. Actions renders the site in a VM (re-runs all code) and Netlify publishes a **preview**.
3. The bot comments the **preview URL** (e.g. `1-merge--your-site.netlify.app/...`).
4. Reviewers read the diff under **Files changed** *and* click the live **Preview**.
5. Preview looks good → **merge** → production site updates automatically.

This is what makes it good for teams, GSoC, and outside contributions.

---

## Part 3 — Can it be automated (no hand work)?

**Short answer: yes for everything per-project, after a one-time human login.** The only
human actions are proving your identity to GitHub and to Netlify *once* (any account
automation requires that). After that, a single script provisions any number of repos
end-to-end with zero clicks. The one step in the talk with *no* API — creating the
fine-grained PAT — is not actually required.

### Step-by-step automation verdict

| # | Setup step | Automatable? | How |
|---|---|---|---|
| 1 | Create GitHub repo | ✅ | `gh repo create YOUR_REPO --public --source=. --push` |
| 2 | Build site locally | ✅ (optional) | `quarto render` / `Rscript -e 'litedown::fuse_site()'` — **not even needed**; the API can create an empty site and let CI fill it |
| 3 | Create Netlify project | ✅ | API `POST /api/v1/sites` or `netlify deploy --site-name …` (implies create) |
| 4 | Name + capture Site ID | ✅ | the create call returns `id` + `ssl_url` in JSON — parse with `jq` |
| 5 | Generate Netlify token | ⚠️ **once, by hand** | web UI or `netlify login` (OAuth). Bootstrap credential — reusable across all repos |
| 6 | Store GitHub secrets | ✅ | `gh secret set NETLIFY_AUTH_TOKEN -b …` / `gh secret set NETLIFY_SITE_ID -b …` |
| 7 | `PAT_GITHUB_PR` | ❌ no API … | …but **eliminable** — use the built-in `GITHUB_TOKEN` (see below) |
| 8 | Add workflow YAML | ✅ | write the file in the script |
| 9 | Add `render.R` | ✅ | write the file in the script |
| 10 | Commit, push, verify | ✅ | `git commit && git push`; poll with `gh run watch` / `gh pr checks` |
| 11 | Link changed pages | ⚠️ | author convenience; "future work" in the talk is to auto-link all changed pages |

### The two irreducible "once, by hand" items (not per-project)
- **`gh auth login`** — authenticate the GitHub CLI once.
- **A Netlify token** — `netlify login` (browser OAuth) or mint one PAT in the UI once.

The *same* `NETLIFY_AUTH_TOKEN` creates unlimited sites, and `gh` then drives everything
else non-interactively. There is no way around a first human login to a service — that's
identity bootstrap, not "hand work" in the workflow sense.

### Eliminating the only un-API-able step (`PAT_GITHUB_PR`)
GitHub deliberately provides **no endpoint to create a personal access token** (for
automation they steer you to GitHub Apps). So the talk's step 7 cannot be scripted *as
written*. But it isn't necessary: a workflow can post PR comments with the auto-injected
`GITHUB_TOKEN`, given the right permission block:

```yaml
permissions:
  contents: read
  pull-requests: write   # lets GITHUB_TOKEN post the preview comment
```
```yaml
    # in the deploy step, swap the secret:
    pat_github_pr: ${{ secrets.GITHUB_TOKEN }}
```

**Caveat:** `GITHUB_TOKEN` is read-only for PRs **opened from forks**. If you need
preview comments on fork PRs, you must either use `pull_request_target` (with the usual
security care around untrusted code) or fall back to a PAT / GitHub App. For a team repo
where contributors push branches (not forks), `GITHUB_TOKEN` is enough and step 7
disappears entirely.

### One-shot provisioning script

After the one-time logins, this provisions a repo end-to-end. Treat it as a template.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── one-time human bootstrap (run once, not per project) ────────────────
#   gh auth login
#   export NETLIFY_AUTH_TOKEN=...   # from app.netlify.com/user/applications/personal
# ────────────────────────────────────────────────────────────────────────
: "${NETLIFY_AUTH_TOKEN:?set NETLIFY_AUTH_TOKEN first}"

SITE_NAME="${1:?usage: provision.sh <site-name> <github-owner/repo>}"
GH_REPO="${2:?usage: provision.sh <site-name> <github-owner/repo>}"

# 1. Create the Netlify site (returns Site ID + URL) — no upload needed.
resp=$(curl -fsS -X POST "https://api.netlify.com/api/v1/sites" \
  -H "Authorization: Bearer $NETLIFY_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$SITE_NAME\"}")
SITE_ID=$(echo "$resp" | jq -r '.id')
SITE_URL=$(echo "$resp" | jq -r '.ssl_url')
echo "Netlify site: $SITE_URL  (id $SITE_ID)"

# 2. Create the GitHub repo from the current directory.
gh repo create "$GH_REPO" --public --source=. --remote=origin || true

# 3. Store secrets (no PAT — workflow uses GITHUB_TOKEN).
gh secret set NETLIFY_AUTH_TOKEN -R "$GH_REPO" -b "$NETLIFY_AUTH_TOKEN"
gh secret set NETLIFY_SITE_ID    -R "$GH_REPO" -b "$SITE_ID"

# 4. Write workflow + render.R + .gitignore (omitted here for brevity; see Parts 1.8–1.9,
#    using permissions: pull-requests: write and pat_github_pr: ${{ secrets.GITHUB_TOKEN }},
#    and netlify_url: $SITE_NAME.netlify.app).

# 5. Ship it.
git add -A && git commit -m "add netlify deploy workflow" && git push -u origin HEAD
echo "Done. Open a PR to get your first preview at https://<branch>--$SITE_NAME.netlify.app"
```

### Bottom line
- **Fully automatable per project:** repo creation, site creation, Site-ID capture,
  secret storage, workflow + `render.R` generation, commit/push, and CI verification.
- **Human, exactly once (reusable forever):** log in to GitHub and obtain a Netlify token.
- **The talk's PAT step:** the only thing with no API — so don't do it; use `GITHUB_TOKEN`
  (works for same-repo PRs; forks need `pull_request_target` or an App).
- So "no hand work required" is achievable for steady-state operation; the irreducible
  minimum is a single one-time authentication to each service.

---

## Appendix

### Why this stack (talk's "Why not…?")
- **GitHub vs GitLab:** GitHub is more popular → easier for others to contribute PRs.
- **quarto vs Jekyll/Hugo:** quarto re-executes R/Python every build and embeds fresh
  results/figures in the HTML. (Jekyll is better only if results should be *frozen*.)
- **Netlify vs GitHub Pages:** Pages has **no per-PR preview** and **requires the
  generated files in the repo** (bloat, slow). Netlify previews each PR and lets the repo
  hold **only source** (fast).

### Example sites from the talk
- animint2 Manual — src `animint/animint-manual-en` → `animint-manual-en.netlify.app`
- data.table blog — src `rdatatable-community/data-table-raft` → `data-table-raft.netlify.app`
- R package docs — `tdhock/mlr3resampling` → `mlr3resampling.netlify.app`; `tdhock/atime` → `atime-docs.netlify.app`

### Open "future work" from the talk
- A PR comment that auto-links **all** changed pages (not just `index.html`).
- A `render.R` that scans `.qmd` files to auto-determine which R packages to install.

### Sources (automation research)
- Netlify CLI `deploy` (non-interactive auth, `--site-name` implies create): <https://cli.netlify.com/commands/deploy/>
- Create sites programmatically with the Netlify API: <https://www.netlify.com/blog/create-sites-programmatically-with-the-netlify-api/>
- GitHub Actions secrets via `gh secret set`: <https://cli.github.com/manual/gh_secret_set>
- No API to create fine-grained PATs (use GitHub Apps): <https://github.com/orgs/community/discussions/120437>
