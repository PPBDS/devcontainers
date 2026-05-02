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

- `ghcr.io/rocker-org/devcontainer/tidyverse` as the FROM line — rocker's devcontainer-flavored tidyverse image. Pinned by SHA digest (the `:4.4` tag floats as Rocker patches the image; the digest freezes us at a known build). Bumping the digest is a deliberate commit.
- System libraries needed by both downstream images:
  - Geospatial: `libgdal-dev`, `libproj-dev`, `libgeos-dev`, `libudunits2-dev`
  - V8 (for `katex`, `V8`): `libnode-dev`
  - Text shaping for `ragg`/`textshaping`: `libfontconfig1-dev`, `libharfbuzz-dev`, `libfribidi-dev`
- GitHub CLI (`gh`), installed from the official apt repo
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
- R CMD check toolchain (`qpdf`, plus what's already in rocker/tidyverse)
- Build tools and headers for compiling packages from source

Does NOT include:

- The `vscode-r-tutorials` extension (developers write tutorials, they don't run them through the extension)
- Pre-installed PPBDS tutorial packages (developers work from source)

This is the image that PPBDS package repos (tutorial.helpers, positron.tutorials, primer, ai.tutorials, etc.) reference in their `.devcontainer/devcontainer.json`.

### `student/` — for taking the class

Audience: students in the data science course.

Contents (in addition to `base`):

- Pre-installed binary version of `tutorial.helpers`, sourced from the PPBDS r-universe (`https://ppbds.r-universe.dev`). Add other course packages here (`primer`, `ai.tutorials`, etc.) when the syllabus needs them baked in.

Does NOT include:

- Package development tooling (devtools, pkgdown, R CMD check deps) — students don't need it and it slows the image
- Source-builds of PPBDS packages — students get binary releases from r-universe
- VS Code settings/extensions (font, theme, `vscode-r-tutorials`) — those live in `codespace-starter`'s `devcontainer.json`, not in this image, so the image stays editor-agnostic
- A workaround for the Codespace `GITHUB_TOKEN` scoping behavior. The default token is repo-scoped by design; students who need to push elsewhere run `gh auth login` once per Codespace. Documented in `codespace-starter`'s README, not patched in the image.

The `student` image is consumed by `PPBDS/codespace-starter`, the GitHub template repository students click "Use this template" on to seed their own repo for the class.

## Tagging and versioning

Each image is published with these tag families:

- `:latest` — most recent successful build from `main`. Convenient for development; not stable.
- `:X.Y.Z` and `:X.Y` — semver tags derived from a GitHub release on this repo. The canonical stable pin.
- `:<semester>` — for the `student` image only: a moving channel like `:fa25`, `:sp26` that points at the semver release blessed for that semester. Lets us patch security fixes within a semester without forcing a manual bump in `codespace-starter`. Applied manually by retagging a tested release; the build workflow does not produce these automatically.

Pin policy:

- `codespace-starter` pins to `:<semester>` and we update that tag deliberately.
- PPBDS package repos may pin to `:latest` for `dev` (David's call) or to a semver tag if they want stability.

The R version is encoded in `base`'s FROM line. We do not publish a separate `:r-4.4`-style tag.

## CI and build

GitHub Actions builds and publishes images on push to `main` and on tagged releases (`v*`). The workflow has two jobs:

1. `build-base` builds and pushes `base` first, and emits the SHA-pinned tag of the just-pushed base.
2. `build-downstream` is a matrix over `[dev, student]` that runs after `build-base`, with `BASE_TAG` passed as a build arg so each downstream build pulls the *exact* base image produced in the same run.

Builds run on Ubuntu; downstream consumers may run the resulting images on Linux, macOS, or Windows hosts via Docker Desktop or Codespaces.

When changing the base image, expect both `dev` and `student` to rebuild. Verify both still work before tagging a release.

## Relationship to other PPBDS repos

- **PPBDS package repos** (tutorial.helpers, positron.tutorials, primer, ai.tutorials, vscode-r-tutorials, others): each contains a `.devcontainer/devcontainer.json` of roughly five lines, referencing `ghcr.io/ppbds/devcontainers/dev:<tag>`. Per-repo customization (extra VS Code extensions, postCreate hooks specific to that package) goes in that file, not in the dev image.

- **`PPBDS/codespace-starter`**: a GitHub template repository. Its `.devcontainer/devcontainer.json` references `ghcr.io/ppbds/devcontainers/student:<semester-tag>`. Students click "Use this template" to create their own repo, then launch a Codespace from it.

Do not put student-facing content (problem sets, tutorial seed files, README instructions for students) in *this* repo. That belongs in `codespace-starter`. This repo only builds the image the template references.

## Coding and style conventions

- R style: tidyverse and functional. Base pipe `|>`, lambda syntax `\(x)`. No `magrittr` `%>%`, no `function(x)` where `\(x)` works.
- Shell scripts: bash, `set -euo pipefail` at the top, shellcheck-clean.
- Dockerfiles: pin versions where it matters, comment non-obvious choices, group RUN steps to keep layers reasonable but don't over-optimize at the cost of readability.
- Prefer direct, opinionated recommendations over hedged presentations of options. If there is a clear best answer for this context, say so and explain why; do not enumerate alternatives the user did not ask for.
- Push back on unsupported claims. Accuracy matters more than reassurance.

## What this repo is not

- Not a place for application code, R packages, or course content.
- Not a template repo. Students do not fork or "Use this template" on this repo. They use `PPBDS/codespace-starter`.
- Not a Feature registry. If we later want to publish reusable devcontainer Features, that goes in a separate repo (`PPBDS/devcontainer-features` or similar).
- Not coupled to GitHub Codespaces specifically. The images should work in any devcontainer-compatible environment (VS Code locally with Docker, JetBrains, GitPod). Avoid Codespaces-only assumptions in the Dockerfiles.
