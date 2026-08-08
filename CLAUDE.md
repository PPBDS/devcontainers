# CLAUDE.md

## Repository purpose

This repository, `PPBDS/devcontainers`, is the single source of truth for development container infrastructure across the PPBDS GitHub organization. It publishes ONE Docker image to the GitHub Container Registry:

    ghcr.io/ppbds/devcontainer

Every consumer — students taking the course (via `PPBDS/codespace-starter`) and developers working on PPBDS packages (`PPBDS/primer` etc.) — uses this same image, referenced by tag from a short `.devcontainer/devcontainer.json`.

Do not add application code, R packages, or tutorial content to this repo. This repo is infrastructure only.

## One-image architecture (since v1.0.0)

Until v0.9.0 this repo published three images (`base` → `dev`/`student`). That trio was collapsed into one image in v1.0.0: the dev image's delta over base was just qpdf + five R packages (trivial against the ~4.6 GB full image), its only consumer was `PPBDS/primer`, and the base→downstream split cost real money — `BASE_TAG` build-arg threading, a two-job CI dependency, and cross-image permission bugs (the 2026-07 root-vs-rstudio lock-file failure happened exactly at that boundary). The old `devcontainers/base`, `devcontainers/dev`, and `devcontainers/student` packages remain on GHCR at their final tags (0.9.0) so old pins keep working, but they receive no new versions.

Everything lives in the single root `Dockerfile`. Its layer order mirrors the old layering and the comments in it are the canonical documentation of what's installed and why. Summary:

- `ghcr.io/rocker-org/devcontainer/tidyverse` as the FROM line, pinned by SHA digest (the `:4.5` tag floats as Rocker patches; the digest freezes us at a known build; bumping it is a deliberate commit).
- System libraries: geospatial (GDAL/PROJ/GEOS/udunits for sf), text shaping (ragg/textshaping), `cmake`, `libuv1-dev` (fs ≥ 2.1.0 sysreq — silences a phantom pak warning), `qpdf` (R CMD check PDF checks).
- The V8 R package needs **no** system lib — its P3M binary is statically linked. A metadata-only `libnode-dev-virtual` package (Provides: libnode-dev/libv8-dev, ships no files) satisfies pak's sysreqs check; see the block in the Dockerfile. Relatedly, `ENV PKG_SYSREQS=false` is set image-wide so pak never tries to `sudo apt` sysreqs (the non-root rstudio user can't); add new system deps to the apt block, not via pak.
- GitHub CLI (`gh`); Quarto (pinned ARG); `arf` (Rust R console, pinned ARG, installed as rstudio, symlinked to `/usr/local/bin/arf` for consumer config stability).
- Five AI coding CLIs, shipped with **no credentials** (sign-in on first run recommended; API keys via Codespaces user secrets as fallback): `claude` (pinned), `codex` (pinned, startup update check pre-disabled), `agy` (Antigravity — installer has NO version pin, floats; replaced the Gemini CLI Google EOL'd 2026-06-18), `grok` (Grok Build, xAI — pinned; sign in with a SuperGrok / X Premium+ plan), `aider` (pipx, pinned since v1.0.8, key-only).
- `pak` (installer), `httpgd` (graphics device — comes from rocker's r-packages feature; deliberately NOT reinstalled here).
- Modeling stack from the CURRENT P3M snapshot: `tidymodels`, `bonsai`, engines (`xgboost`, `lightgbm`, `randomForest`, `ranger`, `glmnet`), `catboost` (pinned GitHub release binary, amd64), `brms` (+ explicit `BH`/`RcppEigen`/`RcppParallel` — rstan binary installs skip its LinkingTo deps, but runtime Stan compilation needs them).
- Inference-reporting + presentation set: `gt`, `marginaleffects`, `patchwork`, `easystats` — used pervasively in the primer book and tutorials. Since the course-package install moved to `dependencies = TRUE` (2026-07), most arrive via the tutorial packages' Imports/Suggests anyway; the explicit block stays for `patchwork` (book-only) and as belt-and-suspenders. easystats' on-attach CRAN version check / "needs update" banner is disabled via `Rprofile.site` (`easystats.quiet` + an attach hook that preserves component auto-attach — see the Dockerfile block; do NOT replace it with `EASYSTATS_QUIET=1`, which would stop the components attaching at all).
- Package-development set (the old dev image): `devtools`, `pkgdown`, `roxygen2`, `testthat`, `usethis`.
- Course packages from GitHub source (`PPBDS/tutorial.helpers`, `PPBDS/vscode.tutorials`, `PPBDS/misc.tutorials`, `PPBDS/primer.tutorials` — split out of the primer repo 2026-07 so installs stop downloading the 183 MB primer tarball; don't point it back at the subdir), installed **as rstudio** with `upgrade = TRUE` (see the xfun ABI note in the Dockerfile) and `dependencies = TRUE` — **each package's Suggests list is the contract for what students need at tutorial runtime** (2026-07); every Suggests entry is baked and loaded by a smoke test, so keep those lists curated. NONE of these are refreshed at Codespace create anymore (the live primer.tutorials refresh was retired 2026-07-30; codespace-starter keeps the recipe dormant in its devcontainer.json comments); all four ship at image-baked versions, updated via the next release + pin bump.
- Interactive viz + Shinylive (R: `plotly`, `leaflet`, `DT`, `crosstalk`, `shiny`, `shinylive`).
- Mapping/census stack: `sf`, `tidycensus` (+`tigris`), `mapgl` (token-free WebGL maps via `maplibre()` + CARTO styles), `crsuggest`, `idbr`. Live tidycensus/idbr queries need each student's free Census API key (the API rejects keyless requests). `mapboxapi` deliberately excluded (needs per-student Mapbox account).
- Python data-science stack via `uv` into a group-writable venv at `/opt/venv` from a fully pinned lockfile (`requirements.lock`, compiled from `requirements.txt` — edit the .txt and recompile to bump). System CPython, seeded pip, default `python` on PATH, registered "Python (data science)" Jupyter kernel; Quarto runs Python docs via the jupyter engine, so reticulate is not needed (RETICULATE_PYTHON is still set).
- Observable Framework CLI (pinned npm install); Quarto's `{ojs}` cells need nothing extra.
- Headless workarounds (`xdg-open` stub, `BROWSER=/usr/bin/true`).
- A custom **first-run terminal notice** (`first-run-notice.txt`) replacing the stock Codespaces welcome: it tells students setup is still finishing and to wait for codespace-starter's "YOUR CODESPACE IS READY" banner — bridging the ~30 s silent gap between terminal attach and welcome.sh. Keep the banner text in sync with welcome.sh.
- The **R Tutorials VS Code extension** (`PPBDS.vscode-r-tutorials`, pinned via the `RT_EXT_VERSION` build arg): the Open VSX .vsix is pre-extracted into `/home/rstudio/.vscode-remote/extensions/` at build time so the Activity Bar icon exists from the first window paint. It can NOT go in codespace-starter's `extensions` list (that installs from the Microsoft Marketplace only; we publish to Open VSX), and attach-time vsix installs need a window reload before the icon appears (tried, rejected). Deliberate exception to editor-agnosticism — non-VS-Code consumers ignore the dir. Shipping a new extension version = publish to Open VSX, bump `RT_EXT_VERSION`, cut a release.

### Install-user convention (IMPORTANT)

Root installs poison R's site-library for later non-root installs: pak/pkgdepends lock files created by root are group-unreadable and later rstudio-user installs die with `filelock::lock(): Permission denied` (broke the student build, 2026-07). The Dockerfile's rules:

1. R package installs run **as rstudio** wherever possible (everything after the `USER rstudio` divider).
2. The root-installed R stacks (modeling, inference/presentation) are followed by the hardening step: `rm -rf site-library/_cache` + `chmod -R g+rwX`.
3. The "praise" smoke test proves a non-root install works, at build time.

Keep the smoke tests up to date when adding or removing packages — every Dockerfile section ends with one, and the build fails if any baked package can't load (this catches binary-ABI mismatches like the learnr/xfun failure at build time rather than at Codespace launch).

## Tagging and versioning

Tag families on `ghcr.io/ppbds/devcontainer`:

- `:latest` — most recent successful build from `main`. Convenient for development; not stable.
- `:X.Y.Z` and `:X.Y` — semver tags from a GitHub release on this repo. The canonical stable pin.

Pin policy:

- `codespace-starter` pins a specific `:X.Y.Z` and bumps it deliberately. Never `:latest` in student-facing config.
- `PPBDS/primer` (and other package repos) also pin a specific `:X.Y.Z` (David's call, 2026-07 — previously dev floated on `:latest`).
- Version numbers increment **only the last digit** (0.9.0 → 1.0.0 was an explicit exception for the one-image consolidation; from v1.0.0: 1.0.1, 1.0.2, …). Bump more only when David explicitly asks.

The R version is encoded in the FROM line. We do not publish a separate `:r-4.5`-style tag.

## CI and build

`.github/workflows/build.yml` — a single job that builds and pushes the image on push to `main`, on tagged releases (`v*`), and on `workflow_dispatch` (used for pre-merge branch validation). Builds run on Ubuntu; the image runs on Linux/macOS/Windows hosts via Docker Desktop or Codespaces. A `prune-caches` job runs after every build (standing policy, David 2026-08): Actions caches not used by the last two builds are deleted — `mode=max` caching of this image overflows the 10 GB repo budget in a few builds, and GitHub's LRU eviction then thrashes layers unpredictably.

## Release & rollout runbook

`devcontainers` (this repo) and `codespace-starter` are kept **separate on purpose** (release-tag cleanliness + blast-radius isolation: a bad image push can't break student launches until the pin is bumped). A coordinated change is two PRs across two repos (three if `PPBDS/primer`'s pin should move too).

### Step 0 — does the change need a new image release?

- **YES — image content changed:** the `Dockerfile`, `requirements.txt`/`.lock`, baked packages, or system libs. → Do **A** then **B**.
- **NO — `codespace-starter` launcher-only:** its `devcontainer.json` VS Code `settings`/`extensions`/comments, `connect-repo.sh`, `welcome.sh`, or docs. → Skip **A**. Just merge to `codespace-starter` `main`; the Codespaces prebuild refreshes automatically.

### A — cut an image release (in `devcontainers`)

1. Branch off `main`.
2. Make the change. Update the matching **smoke test** and **this CLAUDE.md** if the package/lib set changed. **If the release's purpose is refreshing course packages from GitHub HEAD (no other Dockerfile change), bump the `COURSE_PKG_REFRESH` date ARG** — Docker caches RUN layers by instruction text, so without the bump a rebuild is a full cache hit that ships stale packages while reporting success in ~30 s (bit us 2026-07-27). A ~30-second "successful" build is always a cache hit, never a refresh.
3. **Validate before merging:** `gh workflow run build.yml --ref <branch>`, then watch it green. The build is heavy (source-builds `primer.*`, brms/Stan compile) — allow ~25 min. To introspect a published image cheaply, push a throwaway push-triggered workflow that does `docker run <image> …`, read the log, delete the branch.
4. PR → `gh pr merge --merge --delete-branch` → sync `main`.
5. Version: increment the last digit of the latest tag (see Tagging above).
6. `gh release create vX.Y.Z --target main` → the tag build publishes `ghcr.io/ppbds/devcontainer:X.Y.Z` and moves `:X.Y`.
7. Watch the tag build green and **confirm the tag is on GHCR** before repinning (query the GHCR manifest, don't assume).

### B — roll it out (consumers)

**The pin lives in FIVE places (2026-07). Bump them together, every release** — a lagging pin means that repo's CI validates against an image students no longer run:

- `codespace-starter` → `.devcontainer/devcontainer.json` (the student launcher; its pin comment repeats this list).
- `primer.tutorials`, `misc.tutorials`, `vscode.tutorials` → each pins the image in `.github/workflows/R-CMD-check.yaml`, in the `student-env-render` job that renders every tutorial inside this exact image.
- `PPBDS/primer` → `.devcontainer/devcontainer.json` (only if its pin should move).

8. `codespace-starter`: branch; bump the `"image"` pin **and** the "pinned to vX.Y.Z" comment; fold related comment/postCreateCommand edits into the same PR. PR → merge → sync.
9. The three tutorial repos: bump the `image:` tag in each `student-env-render` job (one line per repo, direct to main is fine). Their next CI run then validates the tutorials against the new image.
10. Watch the **Codespaces prebuild** — the Actions run named `.devcontainer/devcontainer.json` — go green. (Prebuild affects startup *speed* only; the pin is live on merge.)
11. `PPBDS/primer` (only if its pin should move): same one-line bump.
12. Ask the user to verify in a **fresh** Codespace. (An already-open Codespace won't pick up `devcontainer.json` changes from a `git pull` — it needs *Dev Containers: Rebuild Container*.)

### Conventions

- Commit trailer on every commit, naming whichever Claude model did the work, e.g.: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Never pin student-facing config to `:latest`.
- Report build/prebuild results honestly (status + conclusion), and clean up throwaway diagnostic branches/workflows when done.

## Relationship to other PPBDS repos

- **`PPBDS/codespace-starter`**: the repo students launch their Codespace from. Its `.devcontainer/devcontainer.json` references `ghcr.io/ppbds/devcontainer:X.Y.Z`. Students launch a Codespace on `codespace-starter` itself, then run its `connect-repo.sh` to create and clone a separate personal work repo.
- **PPBDS package repos** (`primer`, `tutorial.helpers`, `ai.tutorials`, …): the intent is a short `.devcontainer/devcontainer.json` referencing this image, with per-repo customization (extensions, hooks) in that file. **Current reality (verified 2026-07): only `PPBDS/primer` has one.** Treat broader adoption as aspirational.

Do not put student-facing content (problem sets, tutorial seed files, student instructions) in this repo — that belongs in `codespace-starter`.

## Coding and style conventions

- R style: tidyverse and functional. Base pipe `|>`, lambda syntax `\(x)`. No `magrittr` `%>%`, no `function(x)` where `\(x)` works.
- Shell scripts: bash, `set -euo pipefail` at the top, shellcheck-clean.
- Dockerfile: pin versions where it matters, comment non-obvious choices, group RUN steps to keep layers reasonable but don't over-optimize at the cost of readability.
- Prefer direct, opinionated recommendations over hedged presentations of options.
- Push back on unsupported claims. Accuracy matters more than reassurance.

## What this repo is not

- Not a place for application code, R packages, or course content.
- Not student-facing. Students never consume this repo directly.
- Not a Feature registry. Reusable devcontainer Features would go in a separate repo.
- Not coupled to GitHub Codespaces specifically. The image should work in any devcontainer-compatible environment; avoid Codespaces-only assumptions in the Dockerfile.
