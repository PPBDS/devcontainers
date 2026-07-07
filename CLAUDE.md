# CLAUDE.md

## Repository purpose

This repository, `PPBDS/devcontainers`, is the single source of truth for development container infrastructure across the PPBDS GitHub organization. It publishes three Docker images to GitHub Container Registry (GHCR), each serving a distinct audience and use case. Other PPBDS repos consume these images via short `.devcontainer/devcontainer.json` files that reference them by tag.

Do not add application code, R packages, or tutorial content to this repo. This repo is infrastructure only.

## Three-image architecture

The repo publishes three images, organized as subdirectories at the root. Each subdirectory contains a `Dockerfile` plus any supporting scripts that get COPYed into the image.

- `base/`    → `ghcr.io/ppbds/devcontainers/base`
- `dev/`     → `ghcr.io/ppbds/devcontainers/dev`     (FROM base)
- `student/` → `ghcr.io/ppbds/devcontainers/student` (FROM base)

### `base/` — shared substrate

Audience: nobody directly. This image is the common foundation for `dev` and `student`.

Contents:

- `ghcr.io/rocker-org/devcontainer/tidyverse` as the FROM line — rocker's devcontainer-flavored tidyverse image. Pinned by SHA digest (the `:4.5` tag floats as Rocker patches the image; the digest freezes us at a known build). Bumping the digest is a deliberate commit.
- System libraries needed by both downstream images:
  - Geospatial: `libgdal-dev`, `libproj-dev`, `libgeos-dev`, `libudunits2-dev`
  - Text shaping for `ragg`/`textshaping`: `libfontconfig1-dev`, `libharfbuzz-dev`, `libfribidi-dev`
  - `cmake` — build tool for source packages like `fs` (pulled in by `primer.tutorials`)
- The `V8` R package needs **no** system lib here — its Posit Package Manager binary is statically linked (bundled libv8). `libnode-dev` is deliberately *not* installed (NodeSource `nodejs`, installed for the npm CLIs, removes any distro `libnode-dev` anyway). A metadata-only `libnode-dev-virtual` package (`Provides: libnode-dev, libv8-dev`, ships no files) satisfies pak's sysreqs check so it doesn't print a phantom "✖ Missing 1 system package: libnode-dev" on every student install that pulls in V8. See the block in `base/Dockerfile`. Relatedly, the `student` image sets `ENV PKG_SYSREQS=false` so pak never tries to `sudo apt` sysreqs at runtime (the non-root user can't), relying on what `base` bakes.
- GitHub CLI (`gh`), installed from the official apt repo
- AI coding-assistant CLIs (course-required tools — the image ships no credentials and is inert until each tool has either an account sign-in or an API key). The recommended path is account sign-in on first run; API keys via Codespaces user secrets (https://github.com/settings/codespaces) are the fallback. Pinned via build args and bumped deliberately, except `agy` (see below):
  - `claude` (Claude Code) — Anthropic. Sign in with a Claude plan, or `ANTHROPIC_API_KEY`.
  - `codex` (Codex CLI) — OpenAI. Sign in with a ChatGPT plan, or `codex login`; does not read `OPENAI_API_KEY`. Startup update check is pre-disabled (`~/.codex/config.toml`), since the CLI is a global install in an immutable image.
  - `agy` (Antigravity CLI) — Google. Sign in with a Google account, or `ANTIGRAVITY_API_KEY`. Replaced the Gemini CLI, which Google EOL'd 2026-06-18 (consumer/free path stopped serving). Installed via Google's `curl … | bash` installer, which offers **no version pin**, so `agy` floats with each rebuild (the CLI smoke test still gates a broken release).
  - `aider` — multi-provider, key-only. Cost-flexible: point it at DeepSeek directly (`DEEPSEEK_API_KEY`), OpenRouter (`OPENROUTER_API_KEY`), or OpenAI (`OPENAI_API_KEY`).
- Quarto, pinned via a build arg
- `arf` (Rust-based R console), pinned via a build arg, installed under the `rstudio` user so it lives at `/home/rstudio/.cargo/bin/arf` — matches what consumer `devcontainer.json`s set as `r.rterm.linux`
- `pak` and `httpgd` (R packages — fast parallel installer and graphics device, both used by every downstream image)
- A shared **modeling stack** (`tidymodels` + engines), installed from the *current* P3M snapshot (overriding rocker's frozen one) so versions are recent enough for the CatBoost engine:
  - `tidymodels`, plus the engine packages it does NOT bundle: `xgboost`, `lightgbm`, `randomForest`, `ranger`, `glmnet`
  - `bonsai` — parsnip bridge for the `lightgbm` and `catboost` engines
  - `catboost` (v1.2.10, pinned) — not on CRAN; installed from its `linux-x86_64` GitHub release binary via `remotes::install_url` with `--no-test-load` (so the end-to-end fit smoke test is the real verification). amd64-only image, so the x86_64 binary suffices.
  - `brms` — Bayesian regression via Stan. Needs `BH`/`RcppEigen`/`RcppParallel` installed explicitly: rstan lists them as `LinkingTo`, but installing rstan as a *binary* skips them, yet Stan *model* compilation at runtime needs them. The brms smoke test compiles a model to verify this end to end.
- An **inference-reporting + presentation set**: `gt` (tables), `marginaleffects` (post-estimation predictions/comparisons/slopes), `patchwork` (ggplot composition), `easystats` (parameters/performance/effectsize meta-package). All four are used pervasively in both PPBDS/primer's `book/` and its tutorials (audited 2026-07) but were previously either absent (only `Suggests` in primer.tutorials, which pak doesn't install) or present only transitively (`gt` via primer.tutorials' Imports). General-purpose, hence base rather than student.
- Headless-container workarounds applicable to any consumer (Codespaces, local Docker, Gateway):
  - `/usr/local/bin/xdg-open` replaced with a no-op stub so tools that try to open a browser (e.g., `quarto publish`) do not error
  - `BROWSER=/usr/bin/true` set as `ENV` for tools that respect `$BROWSER`

Do not install **PPBDS-specific / course** R packages here (e.g. `tutorial.helpers`, `primer.tutorials`) — those belong in the downstream images so each manages its own course-content surface. General-purpose, broadly-shared tooling *does* belong in `base`: the installer (`pak`), graphics device (`httpgd`), and the modeling stack above (`tidymodels`/engines/`catboost`/`brms`), which David chose to share across `dev` and `student` rather than duplicate. The line is course-specific vs general-purpose, not "only pak/httpgd."

### `dev/` — for working *on* PPBDS packages

Audience: David, collaborators, contributors editing PPBDS package source code.

Contents (in addition to `base`):

- `devtools`, `pkgdown`, `roxygen2`, `testthat`, `usethis`
- R CMD check toolchain (`qpdf`, plus the build/check tools already in rocker/tidyverse)

Does NOT include:

- The `vscode-r-tutorials` extension (developers write tutorials, they don't run them through the extension)
- Pre-installed PPBDS tutorial packages (developers work from source)

This image is *intended* as the standard devcontainer for developing PPBDS packages. Adoption is partial: as of 2026-06, **`PPBDS/primer` is the only package repo that actually references it** (and on `dev:latest`, not a pinned tag). Others (`tutorial.helpers`, `ai.tutorials`, `vscode.tutorials`, `misc.tutorials`) have no `.devcontainer/devcontainer.json` pointing here yet. Don't repeat the old aspiration as if it were current fact — verify with code search before claiming consumers.

### `student/` — for taking the class

Audience: students in the data science course.

Contents (in addition to `base`):

- Pre-installed course R packages, all installed from GitHub source via `pak::pkg_install("PPBDS/<name>")` so a fresh image always tracks the latest commit on each package's default branch. The rest of the PPBDS ecosystem expects the development version, not whatever an r-universe build cycle (or CRAN) most recently blessed.
  - `tutorial.helpers` from `PPBDS/tutorial.helpers`
  - `vscode.tutorials` from `PPBDS/vscode.tutorials`
  - `misc.tutorials` from `PPBDS/misc.tutorials`
  - `primer.tutorials` from `PPBDS/primer/primer.tutorials` (a **subdir** of the `primer` repo — note the path; this one also pulls in `primer.data`, a large data package)
  These same four are **also** refreshed to latest on every Codespace create by codespace-starter's `postCreateCommand`. Baking them here pre-installs the dependency tree (so that refresh is a quick update, not a cold build) and is a fallback if GitHub is unreachable. Add further course packages to **both** places (here and the postCreateCommand) following the same pattern.
- A basic **Python data-science stack** so students can work in Python alongside R (numpy, pandas, matplotlib, seaborn, scikit-learn, statsmodels, jupyter, ipykernel). Installed with `uv` into a venv at `/opt/venv` from a fully-pinned lockfile — `student/requirements.lock`, generated from `student/requirements.txt` via `uv pip compile` (edit the `.txt` and recompile to bump). Notable choices, all build-test-verified: the venv uses the **system** CPython (`uv venv --python /usr/bin/python3`, not a managed download); it's the default `python` on `PATH`, `--seed`ed (has its own `pip`), and made **group-writable** (`staff`, like R's site-library) so a student can `pip install` more packages. A `python3` Jupyter kernel ("Python (data science)") is registered system-wide, so Python works in VS Code notebooks and in Quarto `.qmd` chunks — Quarto runs Python-only docs via the **jupyter** engine, so **reticulate is not needed** (and isn't installed; `RETICULATE_PYTHON` is still set so reticulate bridges to this venv if someone does install it). Footprint: ~150 MB compressed / negligible Codespace-creation time (baked into the image, restored by the prebuild).
- **Observable** for interactive JavaScript visualisation. Quarto's bundled `{ojs}` cells render Observable Plot / OJS inside `.qmd` documents (pass R/Python data in via `ojs_define()`) — this needs **nothing extra**, it's part of the baked Quarto (build-test verified). Separately, **Observable Framework** (`@observablehq/framework`, pinned; adds the `observable` CLI for `create`/`preview`/`build`) is installed for building standalone data-app/dashboard projects — ~84 MB on disk, smoke-tested via `observable --version`.
- A **mapping / census stack** for NYT-style tract maps: `sf` (vector geodata — links against the GDAL/PROJ/GEOS/udunits system libs that `base` bakes for exactly this) and `tidycensus` (ACS/decennial data + geometry in one call; pulls in `tigris`). Live `tidycensus` queries need a free per-student Census API key — the Census API rejects keyless requests. Interactive maps come free from the pieces already here: `leaflet` draws `sf` objects, with CARTO basemap tiles instead of Mapbox (no token). The smoke test does an offline `st_sample()` on a CRS-tagged polygon to verify the GDAL/PROJ/GEOS linkage end to end. Rounded out by the rest of the Kyle Walker toolkit: `mapgl` (MapLibre/Mapbox GL htmlwidgets — WebGL vector maps with no token via `maplibre()` + CARTO styles), `crsuggest` (suggests the right projected CRS), and `idbr` (Census International Data Base; same Census API key as tidycensus). `mapboxapi` is deliberately excluded — it needs a per-student Mapbox account/token.
- **Interactive web-viz + Shinylive**, for "fancy" interactive websites that still publish to **static** hosting (GitHub Pages). R htmlwidgets — `plotly`, `leaflet`, `DT`, `crosstalk` (installed via pak, ~70 MB) — and their Python counterparts `plotly`/`altair`/`folium`/`itables` (in `requirements.lock`) emit self-contained client-side JS. `shiny` + `shinylive` (both R and Python) compile Shiny apps to WebAssembly (webR/Pyodide) so even reactive apps run with no server. (Interactive charts *inside* Quarto docs work via these widgets or `{ojs}`; Shinylive embeds via the per-project `quarto-shinylive` extension.)

Does NOT include:

- Package development tooling (devtools, pkgdown, R CMD check deps) — students don't need it and it slows the image
- VS Code settings/extensions (font, theme, `vscode-r-tutorials`) — those live in `codespace-starter`'s `devcontainer.json`, not in this image, so the image stays editor-agnostic
- A workaround for the Codespace `GITHUB_TOKEN` scoping behavior. The default token is repo-scoped by design; students who need to push elsewhere run `gh auth login` once per Codespace. Documented in `codespace-starter`'s README, not patched in the image.

The `student` image is consumed by `PPBDS/codespace-starter`. Students launch a Codespace directly from `codespace-starter` and run its `connect-repo.sh` to create their own separate work repo for the class (they do not fork or "Use this template" — launching from the starter is what lets them benefit from its Codespaces prebuild).

## Tagging and versioning

Each image is published with these tag families:

- `:latest` — most recent successful build from `main`. Convenient for development; not stable.
- `:X.Y.Z` and `:X.Y` — semver tags derived from a GitHub release on this repo. The canonical stable pin.

Pin policy:

- `codespace-starter` pins to a specific `:X.Y.Z` semver tag and we bump that pin deliberately (a one-line edit to its `.devcontainer/devcontainer.json`). No moving "semester" channel — pin by version, period.
- PPBDS package repos may pin to `:latest` for `dev` (David's call) or to a semver tag if they want stability.

The R version is encoded in `base`'s FROM line. We do not publish a separate `:r-4.5`-style tag.

## CI and build

GitHub Actions builds and publishes images on push to `main` and on tagged releases (`v*`). The workflow has two jobs:

1. `build-base` builds and pushes `base` first, and emits the SHA-pinned tag of the just-pushed base.
2. `build-downstream` is a matrix over `[dev, student]` that runs after `build-base`, with `BASE_TAG` passed as a build arg so each downstream build pulls the *exact* base image produced in the same run.

Builds run on Ubuntu; downstream consumers may run the resulting images on Linux, macOS, or Windows hosts via Docker Desktop or Codespaces.

When changing the base image, expect both `dev` and `student` to rebuild. Verify both still work before tagging a release.

Each Dockerfile ends with a smoke test (`R --vanilla -e 'requireNamespace(...)'` over its baked-in packages). The build fails if any package can't load. This catches binary-ABI mismatches (the `learnr`/`xfun` failure mode that bit us during initial build-out) at build time rather than letting them surface as a Codespace launch failure. Keep the smoke tests up to date when adding or removing packages.

## Release & rollout runbook

The steps to take when changing this infrastructure. `devcontainers` (this repo) and `codespace-starter` are kept **separate on purpose** (release-tag cleanliness + blast-radius isolation: a bad image push can't break student launches until the pin is bumped). That separation means a coordinated change is two PRs across two repos — these are the steps.

### Step 0 — does the change need a new image release?

- **YES — image content changed:** any `Dockerfile`, `student/requirements.txt`/`.lock`, baked packages, or system libs. → Do **A** then **B** below.
- **NO — `codespace-starter` launcher-only:** its `devcontainer.json` VS Code `settings`/`extensions`/comments, `connect-repo.sh`, `welcome.sh`, or docs. → Skip **A**. Just merge to `codespace-starter` `main`; the Codespaces prebuild refreshes automatically. No image bump, no version change. (Example: the `r.source.echo` setting, the `PKG_SYSREQS` comment fix.)

### A — cut an image release (in `devcontainers`)

1. Branch off `main`.
2. Make the change. Update the matching **smoke test** and **this CLAUDE.md** if the package/lib set changed.
3. **Validate before merging:** `gh workflow run build.yml --ref <branch>`, then watch it green. This catches build + sysreqs failures *before* a release tag exists. The `student` build is heavy (source-builds `primer.*`, ~4.6 GB) — allow ~20 min. To introspect a published image cheaply (e.g. "is X actually installed?"), push a throwaway **push-triggered** workflow that does `docker run <image> …` or `FROM <image> … RUN …`, read the log, then delete the branch. (We did exactly this to root-cause the `libnode-dev` phantom.)
4. PR → `gh pr merge --merge --delete-branch` → sync `main`.
5. Pick the version: **increment only the last digit** (`Z`), whatever the change — new packages included (David's rule, 2026-07: e.g. 0.9.0 → 0.9.1). Bump `Y` or the major **only when David explicitly asks for it**. `main` is allowed to sit ahead of the latest tag — pure doc/no-op changes can ride with the next real release rather than forcing one.
6. `gh release create vX.Y.Z --target main` → this triggers `build.yml` on the tag, publishing `base`/`dev`/`student:X.Y.Z` and moving `:X.Y`.
7. Watch the tag build green and **confirm `student:X.Y.Z` is on GHCR** before repinning (query the GHCR manifest, don't assume).

### B — roll it out to students (in `codespace-starter`)

8. Branch; bump the `"image": "…/student:X.Y.Z"` pin **and** the "pinned to vX.Y.Z" comment; fold any related comment/`postCreateCommand` edits into the same PR.
9. PR → merge → sync `main`.
10. Watch the **Codespaces prebuild** — the Actions run named `.devcontainer/devcontainer.json` — go green. That's what makes new launches fast on the new image.
11. Ask the user to verify in a **fresh** Codespace. (An already-open Codespace won't pick up `devcontainer.json` changes from a `git pull` — it needs *Dev Containers: Rebuild Container*. The prebuild only affects startup *speed*, not whether a setting/pin is present.)

### Conventions

- Commit trailer on every commit, naming whichever Claude model did the work, e.g.: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Never pin student-facing config to `:latest`.
- Report build/prebuild results honestly (status + conclusion), and clean up throwaway diagnostic branches/workflows when done.

## Relationship to other PPBDS repos

- **PPBDS package repos** (tutorial.helpers, primer, ai.tutorials, etc.): the *intent* is that each contains a short `.devcontainer/devcontainer.json` referencing `ghcr.io/ppbds/devcontainers/dev:<tag>`, with per-repo customization (extra extensions, package-specific postCreate hooks) in that file rather than the dev image. **Current reality (verified 2026-06): only `PPBDS/primer` does, on `dev:latest`.** The rest haven't adopted it. So `dev` is a real but barely-used image — treat "the org depends on it" as aspirational, not load-bearing. (Note: `PPBDS/vscode-r-tutorials` is a TypeScript VS Code extension repo, not an R package — different devcontainer needs, not a consumer of `dev`.)

- **`PPBDS/codespace-starter`**: the repo students launch their Codespace from. Its `.devcontainer/devcontainer.json` references `ghcr.io/ppbds/devcontainers/student:X.Y.Z` (a specific semver tag). Students launch a Codespace on `codespace-starter` itself, then run its `connect-repo.sh` to create and clone a separate personal work repo where they save their work.

Do not put student-facing content (problem sets, tutorial seed files, README instructions for students) in *this* repo. That belongs in `codespace-starter`. This repo only builds the image that `codespace-starter` references.

## Coding and style conventions

- R style: tidyverse and functional. Base pipe `|>`, lambda syntax `\(x)`. No `magrittr` `%>%`, no `function(x)` where `\(x)` works.
- Shell scripts: bash, `set -euo pipefail` at the top, shellcheck-clean.
- Dockerfiles: pin versions where it matters, comment non-obvious choices, group RUN steps to keep layers reasonable but don't over-optimize at the cost of readability.
- Prefer direct, opinionated recommendations over hedged presentations of options. If there is a clear best answer for this context, say so and explain why; do not enumerate alternatives the user did not ask for.
- Push back on unsupported claims. Accuracy matters more than reassurance.

## What this repo is not

- Not a place for application code, R packages, or course content.
- Not student-facing. Students never consume this repo directly; they launch a Codespace from `PPBDS/codespace-starter` and run its `connect-repo.sh`.
- Not a Feature registry. If we later want to publish reusable devcontainer Features, that goes in a separate repo (`PPBDS/devcontainer-features` or similar).
- Not coupled to GitHub Codespaces specifically. The images should work in any devcontainer-compatible environment (VS Code locally with Docker, JetBrains, GitPod). Avoid Codespaces-only assumptions in the Dockerfiles.
