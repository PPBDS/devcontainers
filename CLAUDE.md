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
  - V8 (for `katex`, `V8`): `libnode-dev`
  - Text shaping for `ragg`/`textshaping`: `libfontconfig1-dev`, `libharfbuzz-dev`, `libfribidi-dev`
- GitHub CLI (`gh`), installed from the official apt repo
- AI coding-assistant CLIs (course-required tools — the image ships no credentials and is inert until each tool has either an account sign-in or an API key). The recommended path is account sign-in on first run; API keys via Codespaces user secrets (https://github.com/settings/codespaces) are the fallback. Pinned via build args and bumped deliberately, except `agy` (see below):
  - `claude` (Claude Code) — Anthropic. Sign in with a Claude plan, or `ANTHROPIC_API_KEY`.
  - `codex` (Codex CLI) — OpenAI. Sign in with a ChatGPT plan, or `codex login`; does not read `OPENAI_API_KEY`. Startup update check is pre-disabled (`~/.codex/config.toml`), since the CLI is a global install in an immutable image.
  - `agy` (Antigravity CLI) — Google. Sign in with a Google account, or `ANTIGRAVITY_API_KEY`. Replaced the Gemini CLI, which Google EOL'd 2026-06-18 (consumer/free path stopped serving). Installed via Google's `curl … | bash` installer, which offers **no version pin**, so `agy` floats with each rebuild (the CLI smoke test still gates a broken release).
  - `aider` — multi-provider, key-only. Cost-flexible: point it at DeepSeek directly (`DEEPSEEK_API_KEY`), OpenRouter (`OPENROUTER_API_KEY`), or OpenAI (`OPENAI_API_KEY`).
- Quarto, pinned via a build arg
- `arf` (Rust-based R console), pinned via a build arg, installed under the `rstudio` user so it lives at `/home/rstudio/.cargo/bin/arf` — matches what consumer `devcontainer.json`s set as `r.rterm.linux`
- `pak` and `httpgd` (R packages — fast parallel installer and graphics device, both used by every downstream image)
- Headless-container workarounds applicable to any consumer (Codespaces, local Docker, Gateway):
  - `/usr/local/bin/xdg-open` replaced with a no-op stub so tools that try to open a browser (e.g., `quarto publish`) do not error
  - `BROWSER=/usr/bin/true` set as `ENV` for tools that respect `$BROWSER`

Do not install PPBDS-specific or course R packages here. Application package installation belongs in the downstream images so each can manage its own dependency surface. Only shared dev tooling (`pak`, `httpgd`) belongs in `base`.

### `dev/` — for working *on* PPBDS packages

Audience: David, collaborators, contributors editing PPBDS package source code.

Contents (in addition to `base`):

- `devtools`, `pkgdown`, `roxygen2`, `testthat`, `usethis`
- R CMD check toolchain (`qpdf`, plus the build/check tools already in rocker/tidyverse)

Does NOT include:

- The `vscode-r-tutorials` extension (developers write tutorials, they don't run them through the extension)
- Pre-installed PPBDS tutorial packages (developers work from source)

This is the image that PPBDS package repos (tutorial.helpers, positron.tutorials, primer, ai.tutorials, etc.) reference in their `.devcontainer/devcontainer.json`.

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

## Relationship to other PPBDS repos

- **PPBDS package repos** (tutorial.helpers, positron.tutorials, primer, ai.tutorials, etc.): each *should* contain a `.devcontainer/devcontainer.json` of roughly five lines, referencing `ghcr.io/ppbds/devcontainers/dev:<tag>`. Per-repo customization (extra VS Code extensions, postCreate hooks specific to that package) goes in that file, not in the dev image. Migration to this image is in progress; not all repos have switched yet. (Note: `PPBDS/vscode-r-tutorials` is a TypeScript VS Code extension repo, not an R package — it has different devcontainer needs and is not a consumer of `dev`.)

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
