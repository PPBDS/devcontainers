# CLAUDE.md

## Repository purpose

This repository, `PPBDS/devcontainers`, is the single source of truth for development container infrastructure across the PPBDS GitHub organization. It publishes three Docker images to GitHub Container Registry (GHCR), each serving a distinct audience and use case. Other PPBDS repos consume these images via short `.devcontainer/devcontainer.json` files that reference them by tag.

Do not add application code, R packages, or tutorial content to this repo. This repo is infrastructure only.

## Three-image architecture

The repo publishes three images, organized as subdirectories at the root:

- `base/`    → `ghcr.io/ppbds/devcontainers/base`
- `dev/`     → `ghcr.io/ppbds/devcontainers/dev`     (FROM base)
- `student/` → `ghcr.io/ppbds/devcontainers/student` (FROM base)

### `base/` — shared substrate

Audience: nobody directly. This image is the common foundation for `dev` and `student`.

Contents:

- Rocker tidyverse image as the FROM line (pin to a specific R version, do not float on `:latest`)
- System libraries needed by both downstream images (geospatial libs, V8/Node for katex, anything else surfaced by past GitHub Actions failures)
- Quarto
- radian, httpgd
- Locale, timezone, and other environment basics

Do not install R packages here beyond what Rocker tidyverse already provides. Package installation belongs in the downstream images so each can manage its own dependency surface.

### `dev/` — for working *on* PPBDS packages

Audience: David, collaborators, contributors editing PPBDS package source code.

Contents (in addition to `base`):

- devtools, pkgdown, roxygen2, testthat, usethis, renv
- R CMD check toolchain
- Anything else needed to build, test, document, and release R packages
- Build tools and headers for compiling packages from source

Does NOT include:

- The `vscode-r-tutorials` extension (developers write tutorials, they don't run them through the extension)
- Pre-installed PPBDS tutorial packages (developers work from source)

This is the image that PPBDS package repos (tutorial.helpers, positron.tutorials, primer, ai.tutorials, etc.) reference in their `.devcontainer/devcontainer.json`.

### `student/` — for taking the class

Audience: students in the data science course.

Contents (in addition to `base`):

- Pre-installed binary versions of tutorial.helpers, primer, ai.tutorials, and any other packages students need
- VS Code customizations: `vscode-r-tutorials` extension, opinionated settings (font, theme defaults, terminal config)
- The GitHub auth `postAttachCommand` fix that resolves the `GITHUB_TOKEN` scoping issue for students authenticating to GitHub from inside a Codespace
- Any other student-facing quality-of-life setup

Does NOT include:

- Package development tooling (devtools, pkgdown, R CMD check deps) — students don't need it and it slows the image
- Source-builds of PPBDS packages — students get the binary releases

The `student` image is consumed by `PPBDS/student-template` (formerly `PPBDS/codespace-starter`), which is the GitHub template repository students click "Use this template" on to seed their own repo for the class.

## Tagging and versioning

Each image is published with multiple tags:

- `:latest` — most recent successful build from `main`
- `:X.Y.Z` — semver tag matching a GitHub release on this repo
- `:r-4.4` (or similar) — pin to a major R version when relevant

Downstream repos should NOT pin to `:latest` for anything that needs to be stable across a semester. The student template in particular should pin to a specific semver tag and only bump deliberately between semesters.

## CI and build

GitHub Actions builds and publishes images on push to `main` and on tagged releases. The workflow uses a matrix across the three subdirectories. Builds run on Ubuntu; downstream consumers may run the resulting images on Linux, macOS, or Windows hosts via Docker Desktop or Codespaces.

When changing the base image, expect both `dev` and `student` to rebuild. Verify both still work before tagging a release.

## Relationship to other PPBDS repos

- **PPBDS package repos** (tutorial.helpers, positron.tutorials, primer, ai.tutorials, vscode-r-tutorials, others): each contains a `.devcontainer/devcontainer.json` of roughly five lines, referencing `ghcr.io/ppbds/devcontainers/dev:<tag>`. Per-repo customization (extra VS Code extensions, postCreate hooks specific to that package) goes in that file, not in the dev image.

- **`PPBDS/student-template`** (the renamed `codespace-starter`): a GitHub template repository. Its `.devcontainer/devcontainer.json` references `ghcr.io/ppbds/devcontainers/student:<pinned-tag>`. Students click "Use this template" to create their own repo, then launch a Codespace from it.

Do not put student-facing content (problem sets, tutorial seed files, README instructions for students) in *this* repo. That belongs in `student-template`. This repo only builds the image the template references.

## Coding and style conventions

- R style: tidyverse and functional. Base pipe `|>`, lambda syntax `\(x)`. No `magrittr` `%>%`, no `function(x)` where `\(x)` works.
- Shell scripts: bash, `set -euo pipefail` at the top, shellcheck-clean.
- Dockerfiles: pin versions where it matters, comment non-obvious choices, group RUN steps to keep layers reasonable but don't over-optimize at the cost of readability.
- When editing files, output the complete file rather than diffs or fragments.
- Prefer direct, opinionated recommendations over hedged presentations of options. If there is a clear best answer for this context, say so and explain why; do not enumerate alternatives the user did not ask for.
- Push back on unsupported claims. Accuracy matters more than reassurance.

## What this repo is not

- Not a place for application code, R packages, or course content.
- Not a template repo. Students do not fork or "Use this template" on this repo. They use `PPBDS/student-template`.
- Not a Feature registry. If we later want to publish reusable devcontainer Features, that goes in a separate repo (`PPBDS/devcontainer-features` or similar).
- Not coupled to GitHub Codespaces specifically. The images should work in any devcontainer-compatible environment (VS Code locally with Docker, JetBrains, GitPod). Avoid Codespaces-only assumptions in the Dockerfiles.
