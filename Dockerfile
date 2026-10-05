# syntax=docker/dockerfile:1.7
#
# THE PPBDS devcontainer image — ghcr.io/ppbds/devcontainer.
#
# One image for everyone: students taking the course (launched via
# PPBDS/codespace-starter) AND developers working on PPBDS packages
# (PPBDS/primer etc.). It replaced the old base/dev/student trio in v1.0.0 —
# the dev image's delta (qpdf + five R packages) was a rounding error against
# the full image, and the split cost more in CI plumbing and cross-image
# permission bugs than it saved. The old images remain on GHCR at their final
# tags but receive no new versions.
#
# Layer order matters and mirrors the old base → dev → student layering:
# system libs and CLIs first (root), R stacks next (root, then hardened),
# then course packages and per-user installs (rstudio), then Python/JS
# (root), then the end-to-end smoke tests.

# Pinned by digest. The :4.6 tag floats as Rocker patches the image; the
# digest freezes us at a known build. To bump: pull :4.6 fresh, copy the
# new digest in, commit deliberately. Do not switch to :4.6 unpinned.
# R version note: this base is R 4.6.1 on ubuntu:noble (verified from the
# image config, 2026-08-09, before the 4.5 → 4.6 migration in v1.1.0; P3M
# noble binaries for R 4.6 were confirmed mature at the same time). The
# R-version smoke test near the bottom fails the build if a digest bump
# ever changes the R minor version unnoticed.
FROM ghcr.io/rocker-org/devcontainer/tidyverse:4.6@sha256:3a9ecbed900f17da528cdb17c3ddc43045fc9b4be7dbd8c61cb7b8a6439bfa6b

# Silence R's OpenTelemetry layer, image-wide and from the first R call.
# shiny/knitr/promises import `otel`, and in the image build every quarto
# render and learnr call printed a red "OpenTelemetry error: there is no
# package called 'otelsdk'" (17× per build since at least v1.1.5): something
# in the build environment names an exporter, otel then tries to load
# otelsdk, which is not baked. The R-specific variable wins over the generic
# OTEL_TRACES_EXPORTER, and "none" selects the no-op provider — the same
# thing otel does when nothing is set. Nobody here wants traces. (Sat lower
# in the file in v1.1.7, so one early step still printed it.)
ENV OTEL_R_TRACES_EXPORTER=none

# Dated P3M snapshot for the R stacks we take NEWER than rocker's frozen
# repo (modeling + inference/presentation blocks below). Was "latest", which
# made rebuilds of the same tag day-dependent; a dated snapshot makes every
# release reproducible. Bump this date (any recent date; P3M snapshots are
# daily) when a release should pick up newer CRAN versions of those stacks.
ARG P3M_SNAPSHOT=2026-10-03

ARG QUARTO_VERSION=1.10.18
# GitHub CLI. Pinned via the release .deb, NOT apt: the cli.github.com apt
# repo serves exactly ONE version (the current one), so an apt pin like
# `gh=2.102.0` would fail the build the day the next gh ships. Unpinned until
# v1.1.6, which is how v1.1.5 silently picked up a gh whose `auth login`
# tried to use the clipboard (the "No clipboard utilities available" warning
# connect-repo now suppresses with --clipboard=false).
ARG GH_VERSION=2.102.0
# (arf was wrongly suspected of the 2026-08 Rplots.pdf regression and briefly
# rolled back to 0.3.4 on a branch; exonerated by a version matrix — the real
# culprit is R 4.6's startup no longer calling a globalenv .First.sys
# override. See the .First shim + smoke test after the arf install.)
ARG ARF_VERSION=0.5.3
ARG NODE_MAJOR=24

# AI CLI versions. Pinned so builds are reproducible and the baked version
# doesn't silently drift behind the registry. Bump deliberately, like
# Quarto/arf. (Antigravity CLI is the exception — its installer offers no
# version pin, so `agy` floats; see the agy install block below.)
ARG CLAUDE_CODE_VERSION=2.1.289
ARG CODEX_VERSION=0.160.0
ARG GROK_VERSION=1.0.46
# aider is pip-distributed; pinned like the npm CLIs (it floated unpinned
# until v1.0.8 — the one exception with a pin mechanism available).
ARG AIDER_VERSION=0.86.2

# VS Code extensions baked into the image from Open VSX (see the extension
# block near the bottom). ALL of the student-facing extensions are baked
# since v1.1.7, not just ours, so nothing installs at attach: the Activity
# Bar is complete from first paint and the "YOUR CODESPACE IS READY" banner
# is literally true. Bump deliberately; a bump is an image release.
#  - PPBDS.vscode-r-tutorials: ours. 1.1.0+ lists and runs tutorials through
#    the learnr2 R package (baked with the course packages — bump together).
#    1.2.0+ can close VS Code's Welcome tab at startup (launcher setting
#    rTutorials.closeWelcomeOnStartup).
#  - REditorSupport.r (vscode-R) 3.x + its hard dependency r-syntax. 3.0
#    replaced the file-watcher session hookup with the bundled `sess` R
#    package, which is baked from this exact .vsix (see the sess block) so
#    students never see the "install sess?" prompt. codespace-starter pins
#    the SAME version in its extensions list — keep the two in lockstep.
#  - quarto, Live Server, PDF viewer, Rainbow CSV: the rest of the launcher's
#    list.
ARG RT_EXT_VERSION=1.2.0
ARG VSCODE_R_VERSION=3.0.1
ARG R_SYNTAX_EXT_VERSION=0.1.4
ARG QUARTO_EXT_VERSION=1.138.0
ARG LIVESERVER_EXT_VERSION=5.7.10
ARG PDF_EXT_VERSION=1.2.2
ARG RAINBOW_CSV_EXT_VERSION=3.24.1

# System libraries needed by the R stacks below.
#  - Geospatial: sf, terra, etc.
#  - text shaping libs: ragg / textshaping (modern ggplot2 graphics)
#  - cmake: build tool for source packages like fs (pulled in by primer.tutorials)
#  - libuv1-dev: fs >= 2.1.0 declares libuv as a sysreq. The P3M binary works
#    without it, but pak prints a phantom "✖ Missing 1 system package:
#    libuv1-dev" on every install that touches fs (i.e. nearly all of them) —
#    same annoyance class as the libnode-dev story below, solved here by just
#    baking the real (small) lib.
#  - qpdf: required by `R CMD check --as-cran` for PDF manual checks (package
#    development; rocker/tidyverse already provides the rest of the
#    build/check toolchain).
#  - Images + animation (for the R magick/gganimate block and the Python
#    Pillow/imageio packages): libmagick++-dev + gsfonts (magick),
#    librsvg2-dev (rsvg), libavfilter-dev (av — the ffmpeg libraries), and the
#    ffmpeg CLI itself, which matplotlib's animation writers and imageio's
#    MP4 path shell out to. rocker/tidyverse already has libpng/libjpeg/
#    libtiff/libwebp. (P3M ships Linux binaries of every R package in that
#    block, so these are RUNTIME needs, not build-time; gifski's P3M binary
#    needs no Rust toolchain.)
# NOTE: libv8/libnode-dev is deliberately NOT installed here. The V8 R package
# binary from Posit Package Manager is statically linked (bundled libv8) and
# needs no system library, AND NodeSource's nodejs (installed below) ships
# overlapping files that would remove a distro libnode-dev anyway. pak is told
# the requirement is satisfied via the metadata-only libnode-dev-virtual package
# further down — see that block for the full rationale.
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libudunits2-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
        cmake \
        libuv1-dev \
        qpdf \
        libmagick++-dev \
        gsfonts \
        librsvg2-dev \
        libavfilter-dev \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI, pinned (GH_VERSION) from the release .deb — see the ARG for why
# not the apt repo. dpkg --print-architecture keeps it arch-portable like the
# Quarto install below. The version check is the smoke test.
RUN arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /tmp/gh.deb \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.deb"; \
    dpkg -i /tmp/gh.deb; \
    rm /tmp/gh.deb; \
    gh --version | grep -F "gh version ${GH_VERSION}"

# AI coding-assistant CLIs. Four tools spanning several providers and billing
# models (aider is itself multi-provider). Students choose which to use. The
# recommended way to authenticate is to SIGN IN on first run with the matching
# account (a flat-rate plan, not metered API calls); an API key supplied via
# Codespaces user secrets (https://github.com/settings/codespaces) is the
# fallback:
#   - claude  (Claude Code, Anthropic)  — sign in with a Claude plan, or ANTHROPIC_API_KEY
#   - codex   (Codex CLI, OpenAI)        — sign in with a ChatGPT plan, or `codex login`
#   - agy     (Antigravity CLI, Google)  — sign in with a Google account, or ANTIGRAVITY_API_KEY
#   - grok    (Grok Build, xAI)          — sign in with a SuperGrok / X Premium+ plan (`grok login`)
#   - aider   (multi-provider)           — key-only: DeepSeek/OpenRouter/OpenAI/Anthropic
#
# NOTE: Google's Gemini CLI was REMOVED. Google EOL'd the consumer Gemini CLI
# on 2026-06-18 — the free/sign-in path stopped serving requests — and pushed
# everyone to Antigravity. The Google slot is now the Antigravity CLI (`agy`,
# installed further below via Google's curl installer, alongside arf).
#
# Node hosts the npm-distributed CLIs (claude, codex, grok). We install from
# NodeSource rather than apt: Ubuntu Noble ships Node 18.x, which is past end of
# life — we want a current Node LTS for the npm CLIs. NodeSource gives us one
# (pinned via NODE_MAJOR above). pipx installs aider into an isolated venv with
# shims in /usr/local/bin (on every user's PATH), avoiding the PEP 668 lockout
# on Noble's system Python.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends \
        nodejs \
        pipx \
    && rm -rf /var/lib/apt/lists/*

# Tell pak that the V8 R package's system requirement is satisfied. pak's
# sysreqs database maps V8 to the Debian package "libnode-dev", but:
#   (1) the V8 binary we get from Posit Package Manager is statically linked
#       (bundled libv8) and needs no system library at all, and
#   (2) NodeSource's nodejs (installed just above) ships overlapping files and
#       removes any distro libnode-dev, so it can't be present anyway.
# Without this, pak prints "✖ Missing 1 system package: libnode-dev" on every
# student install that pulls in V8 (gt, primer.tutorials, …) — alarming noise
# for beginners, even though nothing is actually missing. A metadata-only
# package that Provides libnode-dev/libv8-dev satisfies pak's check the
# canonical Debian way; it ships no files, so it coexists with NodeSource
# nodejs. (Validated against student:0.6.1 to silence the message without
# changing what is actually linked.) The trailing dpkg-query is a build-time
# smoke test: fail the build if the Provides did not register.
RUN mkdir -p /tmp/libnode-dev-virtual/DEBIAN \
    && printf '%s\n' \
        'Package: libnode-dev-virtual' \
        'Version: 1.0' \
        'Architecture: all' \
        'Maintainer: PPBDS <noreply@ppbds.invalid>' \
        'Provides: libnode-dev, libv8-dev' \
        'Description: Virtual provide for libnode-dev / libv8-dev' \
        ' The V8 R package ships a bundled static libv8 and needs no system' \
        ' library; this satisfies pak sysreqs without NodeSource-conflicting pkgs.' \
        > /tmp/libnode-dev-virtual/DEBIAN/control \
    && dpkg-deb --build /tmp/libnode-dev-virtual /tmp/libnode-dev-virtual.deb \
    && dpkg -i /tmp/libnode-dev-virtual.deb \
    && rm -rf /tmp/libnode-dev-virtual /tmp/libnode-dev-virtual.deb \
    && dpkg-query -W -f='${Provides}\n' libnode-dev-virtual | grep -q libnode-dev

ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin

RUN npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@openai/codex@${CODEX_VERSION}" \
        "@xai-official/grok@${GROK_VERSION}" \
    && pipx install "aider-chat==${AIDER_VERSION}"

# Pre-seed Codex CLI config for the runtime user (rstudio). The one setting
# that matters for an immutable image:
#   - check_for_update_on_startup=false: the CLI is a global npm install the
#     runtime user can't overwrite, so a startup update check is pointless
#     noise. The Codex docs say to disable it "when updates are centrally
#     managed" — that's us; CODEX_VERSION above is the deliberate version knob.
# Onboarding tooltips and analytics are left at their defaults. Codex rewrites
# this file as students use it, so nothing here is locked.
RUN install -d -o rstudio -g rstudio /home/rstudio/.codex \
    && printf '%s\n' 'check_for_update_on_startup = false' \
        > /home/rstudio/.codex/config.toml \
    && chown rstudio:rstudio /home/rstudio/.codex/config.toml

# Quarto. Use dpkg --print-architecture so the same Dockerfile works on
# amd64 and arm64 builders.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /tmp/quarto.deb \
        "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${arch}.deb"; \
    dpkg -i /tmp/quarto.deb; \
    rm /tmp/quarto.deb; \
    quarto --version

# Per-user installers, run as rstudio so their binaries land under
# /home/rstudio (arf in ~/.cargo/bin, agy in ~/.local/bin):
#  - arf: Rust-based R console. Path matches what consumer devcontainer.json
#    files reference as r.rterm.linux.
#  - agy: Antigravity CLI, Google's terminal coding agent and the successor to
#    the now-EOL'd Gemini CLI. NOTE: its installer offers NO version pin (always
#    latest), so unlike every other tool here agy floats with each image
#    rebuild. Accepted because there is no pin mechanism; the CLI smoke test
#    below still fails the build if a future release breaks. Auth at runtime is
#    Google sign-in (prints a URL + one-time code, works headless in Codespaces)
#    or an ANTIGRAVITY_API_KEY from Google AI Studio.
USER rstudio
RUN curl --proto '=https' --tlsv1.2 -fsSL \
        "https://github.com/eitsupi/arf/releases/download/v${ARF_VERSION}/arf-console-installer.sh" | sh
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash
USER root

# Symlink both per-user binaries to a stable system path so consumer config
# doesn't hard-code "/home/rstudio/...". If the image's default user ever
# changes, only this Dockerfile needs updating, not every consumer.
RUN ln -s /home/rstudio/.cargo/bin/arf /usr/local/bin/arf \
    && ln -s /home/rstudio/.local/bin/agy /usr/local/bin/agy

# ---- (REMOVED in v1.1.7) vscode-R session-watcher shim for R >= 4.6 -------
# v1.1.2–v1.1.6 appended a `.First` to Rprofile.site that fired vscode-R
# 2.x's globalenv `.First.sys` shadow, because R 4.6 stopped calling it and
# plots silently fell back to Rplots.pdf. vscode-R 3.0 no longer uses that
# mechanism at all: its R_PROFILE_USER profile calls `sess::connect()`
# directly (R/profile.R in the .vsix), so the shim had nothing to fire and
# was deleted along with its `arf headless` smoke test. The replacement
# contract is the `sess` bake below: sess must load, and its version must
# be >= the one bundled in the baked vscode-R, or the extension prompts
# every student to install it. If plots ever regress to PDFs again, check
# THAT first (git history at this line has the old shim if 2.x ever returns).
# -------------------------------------------------------------------------

# pak: fast parallel R package installer, used for every R install below.
RUN R -q -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))'

# tidymodels + a set of modeling engines. All of these are pulled from a
# DATED P3M snapshot (P3M_SNAPSHOT arg — newer than rocker's frozen repo,
# reproducible across rebuilds) so we get versions recent enough for the CatBoost engine (parsnip >= 1.4.0, bonsai >= 0.4.1)
# and current everything else. None of the engine packages ship inside the
# tidymodels meta-package — parsnip only provides the interface, so each
# backend is installed explicitly here:
#   - tidymodels  : the modeling framework (parsnip/recipes/rsample/tune/yardstick/…)
#   - bonsai      : parsnip bridge for the lightgbm AND catboost engines
#   - xgboost, lightgbm, randomForest, ranger, glmnet : tree/regularized engines
#   - brms        : Bayesian regression via Stan — heavy (pulls rstan/StanHeaders);
#                   compiles models at runtime using the rocker C++ toolchain
#   - BH, RcppEigen, RcppParallel : the Boost / Eigen / TBB C++ headers rstan
#   - remotes     : needed for the CatBoost URL install below
# CatBoost is not on CRAN — install its pinned linux-x86_64 release binary via
# remotes::install_url; the INSTALL_opts are what a clean binary install needs
# (per the catboost docs / the 2026-06 Posit tidymodels+catboost blog). The image
# is amd64-only (build.yml sets no platforms), so the x86_64 binary suffices. The
# end-to-end fit smoke test near the bottom proves the engine actually works —
# important, since we install it with --no-test-load.
RUN R -q -e "options(repos = c(P3M = 'https://packagemanager.posit.co/cran/__linux__/noble/${P3M_SNAPSHOT}')); pak::pkg_install(c('tidymodels', 'bonsai', 'remotes', 'xgboost', 'lightgbm', 'randomForest', 'ranger', 'glmnet', 'brms', 'BH', 'RcppEigen', 'RcppParallel'))" \
 && R -q -e 'remotes::install_url("https://github.com/catboost/catboost/releases/download/v1.2.10/catboost-R-linux-x86_64-1.2.10.tgz", INSTALL_opts = c("--no-multiarch", "--no-test-load", "--no-staged-install"))'

# Inference-reporting + presentation packages. Used pervasively in BOTH
# PPBDS/primer's book/ and its tutorials (audited 2026-07). Since the
# course-package install below moved to dependencies = TRUE (2026-07),
# gt/marginaleffects/easystats also arrive via the tutorial packages'
# Imports/Suggests; this explicit block stays for patchwork (book-only,
# in no tutorial package's Suggests) and as belt-and-suspenders for the
# rest:
#   - gt              : presentation-quality tables (1,100+ gt:: calls in the
#                       book; was previously present only transitively via
#                       primer.tutorials' Imports — now a deliberate choice)
#   - marginaleffects : predictions/comparisons/slopes from fitted models —
#                       the book's standard post-estimation workflow
#   - patchwork       : ggplot composition ("p1 + p2")
#   - easystats       : meta-package (parameters/performance/effectsize/see/…)
#                       used across the tutorials
RUN R -q -e "options(repos = c(P3M = 'https://packagemanager.posit.co/cran/__linux__/noble/${P3M_SNAPSHOT}')); pak::pkg_install(c('gt', 'marginaleffects', 'patchwork', 'easystats'))"

# Silence easystats' on-attach update nag. easystats' .onAttach queries CRAN
# LIVE on every library(easystats) (up to a 10 s network wait) and prints a
# red "✖ needs update / Restart the R-Session and update" banner whenever any
# of its ten component packages is behind CRAN's newest SOURCE version. In an
# immutable image built from P3M binaries (which lag CRAN by days, by design)
# that banner is a permanent false alarm — same class as the libnode-dev
# phantom — and it goads students into ad-hoc easystats_update() runs that
# churn the baked library.
#
# TRAP (do not "simplify" this to EASYSTATS_QUIET=1): easystats' kill switch
# returns from .onAttach BEFORE the code that attaches the ten component
# packages (they are Imports, attached manually inside .onAttach). The env
# var alone would silently stop library(easystats) from attaching
# parameters/effectsize/…, breaking the tutorials' usage pattern. So we set
# the quiet option AND register an attach hook that re-attaches the
# components ourselves: same attach behavior, no banner, no CRAN round-trip.
# Lives in Rprofile.site, so it applies to every non-vanilla R session (the
# smoke test below runs WITHOUT --vanilla for exactly that reason).
RUN cat >> /usr/local/lib/R/etc/Rprofile.site <<'EOF'

# easystats: no on-attach CRAN check/update nag; keep component auto-attach.
# See the easystats block in the PPBDS/devcontainers Dockerfile.
options(easystats.quiet = TRUE)
setHook(packageEvent("easystats", "attach"), function(pkgname, libpath) {
  for (p in c("insight", "datawizard", "bayestestR", "correlation",
              "effectsize", "modelbased", "parameters", "performance",
              "report", "see")) {
    suppressPackageStartupMessages(
      library(p, character.only = TRUE, warn.conflicts = FALSE)
    )
  }
})
EOF

# Smoke test: attaching easystats (site profile active, hence no --vanilla)
# must attach the component packages and print NO update nag.
RUN out="$(R -q -e 'library(easystats); stopifnot(all(paste0("package:", c("effectsize", "parameters", "performance", "see")) %in% search())); cat("easystats attach OK\n")' 2>&1)" \
    && echo "$out" \
    && echo "$out" | grep -q "easystats attach OK" \
    && ! echo "$out" | grep -q "Restart the R-Session"

# httpgd (graphics device for the VS Code R extension) is intentionally
# NOT installed here: the rocker devcontainer base already bakes it in via
# its r-packages feature ("packages": "httpgd"), so a second install was
# pure redundancy. Do not re-add it. The smoke test at the bottom of this
# Dockerfile asserts httpgd loads, so if a future base image ever drops
# it, the build fails loudly here instead of students hitting a missing
# graphics device at runtime.

# Headless-container workarounds: any consumer (Codespaces, local Docker,
# JetBrains Gateway) lacks a desktop, so anything that tries to open a
# browser fails. Stub xdg-open and set BROWSER to a no-op.
RUN printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open
ENV BROWSER=/usr/bin/true

# All R installs above ran as root, so the resulting package dirs are
# root-owned with group-read-only permissions. Restore rocker's convention
# of group-writable site-library so the runtime user (rstudio, in staff
# group) can install/update packages — and so package-load paths that
# touch lock files or caches don't trip permission errors.
#
# Two hardenings, both for the same failure class (a root pak run poisons
# the library for later non-root installs; see the rstudio-user rationale
# below):
#  - rm -rf _cache: pkgdepends locks site-library/_cache/<pkg>.lock during
#    installs. Locks created by ROOT here are group-unreadable (root's
#    umask), and a later rstudio-user pak run then dies with
#    "filelock::lock(): Cannot open lock file: Permission denied" — this
#    broke the student build (2026-07). The dir is pure scratch; delete it.
#  - g+rwX (not just g+w): write alone leaves group-READ missing on any
#    file root created without it, and no traverse on such dirs.
RUN rm -rf /usr/local/lib/R/site-library/_cache \
    && chmod -R g+rwX /usr/local/lib/R/site-library

# Never let pak try to `sudo apt-get install` system requirements. The system
# libraries our packages need are baked above; pak running as the non-root
# rstudio user can't sudo, and (e.g. for V8's libnode-dev) it even mis-detects
# baked libs as missing and tries anyway, which fails the build / postCreate /
# a student's runtime install. With this off pak still PRINTS any sysreqs but
# builds against the baked libs. (Add new system deps to the apt block at the
# top, not via pak.) Applies to the rstudio-user installs below, to
# codespace-starter's postCreateCommand, and to runtime installs.
ENV PKG_SYSREQS=false

# ── Everything below installs as rstudio, not root ───────────────────────────
# This is the design fix for a class of permissions bugs: when pak runs as
# root, it drops lock files in site-library as -rw--w---- (group write but no
# read, due to root's restrictive umask), which then blocks every subsequent
# install by the non-root rstudio user with "filelock::lock(): Permission
# denied". Running as rstudio in the first place means the lock files get a
# normal umask and never poison the library for later installs.
#
# This relies on rocker's site-library being drwxrwsr-x with group=staff and
# rstudio in the staff group (plus the g+rwX hardening above).
USER rstudio

# Package-development R packages (the old dev image's payload). No
# `upgrade = TRUE` here — these have stable, well-behaved binary builds in
# P3M and haven't shown the ABI-mismatch failure mode in practice. The smoke
# test below fails the build if that ever changes.
RUN R -q -e 'pak::pkg_install(c("devtools", "pkgdown", "roxygen2", "testthat", "usethis"))' \
    && R --vanilla -e 'for (p in c("devtools", "pkgdown", "roxygen2", "testthat", "usethis")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Course R packages, all installed from GitHub source via pak so a fresh
# image always tracks the latest commit on each package's default branch.
# This matches PPBDS practice — the rest of the PPBDS ecosystem expects
# the development version, not whatever an r-universe build cycle (or
# CRAN) most recently blessed.
#
# NONE of these four are refreshed at Codespace create anymore (the live
# primer.tutorials refresh was retired 2026-07-30; codespace-starter keeps
# the recipe dormant in its devcontainer.json). All four ship at whatever
# versions this image baked; updates reach students via the next image
# release + pin bump. If the dormant refresh is ever revived, the baked
# copies keep it a quick single-package update (deps pre-installed) and
# remain the fallback if GitHub is unreachable at create time.
# Note primer.tutorials was SPLIT OUT of the primer repo
# (2026-07): as a subdir install ("PPBDS/primer/primer.tutorials") every
# install downloaded the full ~183 MB primer tarball — book, class
# exercises — to deliver a ~4 MB package, at every image build AND every
# Codespace create. Do not point this back at the subdir path.
#
# upgrade = TRUE forces pak to pull the latest version of every
# transitive dep (learnr, knitr, rmarkdown, xfun, ...). Without this, a
# binary dep built against a newer version of xfun than what rocker
# shipped fails to load with "object 'attr' is not exported by
# 'namespace:xfun'".
#
# dependencies = TRUE additionally installs each of the four packages'
# Suggests (top-level only, not Suggests-of-Suggests). This is the
# contract (2026-07): a tutorial package's Suggests list IS the set of
# packages students need at tutorial runtime. Tutorials load them with
# library() or reference them as tidymodels engine strings
# (set_engine("LiblineaR")), so pak's hard-deps-only default left
# students hitting install walls that those repos' all-Suggests CI
# could not see (the katex incident, 2026-07). Keep Suggests curated
# in those repos: every entry ships in this image. Smoke test 1b
# below loads each one.
# CACHE-BUST KNOB. Docker caches RUN layers by instruction text, so a rebuild
# with no Dockerfile change reuses this layer and silently ships STALE course
# packages — a "refresh primer.tutorials" release completed in 28 s as a full
# cache hit (2026-07-27) and delivered bit-identical bits. Bump this date in
# any release whose purpose is picking up new course-package commits from
# GitHub HEAD; layers above stay cached, this one and everything after rebuild.
#
# learnr2 (PPBDS/learnr2, not on CRAN, no releases yet — floats on HEAD with
# the course packages, same refresh knob) is what the R Tutorials VS Code
# extension (RT_EXT_VERSION >= 1.1.0) calls to list and run tutorials:
# learnr2::available_tutorials() and learnr2::run_tutorial(), which hands a
# classic learnr tutorial to learnr. No course package depends on it yet, so
# it is named here explicitly; without it the Tutorials panel is dead.
ARG COURSE_PKG_REFRESH=2026-10-05
RUN echo "course-package refresh: ${COURSE_PKG_REFRESH}" \
 && R -q -e 'pak::pkg_install(c( \
        "PPBDS/tutorial.helpers", \
        "PPBDS/vscode.tutorials", \
        "PPBDS/misc.tutorials", \
        "PPBDS/primer.tutorials", \
        "PPBDS/learnr2" \
    ), upgrade = TRUE, dependencies = TRUE)'

# Smoke test 1: every baked-in package and the learnr/knitr/rmarkdown
# chain must all load. The original learnr/xfun ABI mismatch failure
# would have been caught here at build time.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "misc.tutorials", "primer.tutorials", "learnr2", "learnr", "knitr", "rmarkdown")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Smoke test 1b: every Suggests of the four course packages must load —
# Suggests is the ships-to-students contract (see the install block
# above). Reads the lists from the installed DESCRIPTIONs, so it
# self-maintains as those repos curate their Suggests.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "misc.tutorials", "primer.tutorials")) { s <- utils::packageDescription(p, fields = "Suggests"); if (is.na(s)) next; deps <- trimws(sub("[(].*", "", strsplit(s, ",")[[1]])); for (d in deps[nzchar(deps)]) if (!requireNamespace(d, quietly = TRUE)) stop("Suggests smoke test: ", d, " (suggested by ", p, ") failed to load") }'

# Smoke test 2: rstudio can install a fresh package into site-library
# without permission errors. Catches the "root-built image leaves
# unwritable lock files" regression at build time instead of at
# first-student-pak-call time. praise is tiny (~5KB) and dependency-free.
RUN R --vanilla -e 'install.packages("praise", repos = "https://cloud.r-project.org"); if (!requireNamespace("praise", quietly = TRUE)) stop("rstudio cannot install into site-library — check site-library permissions above")' \
 && R --vanilla -e 'remove.packages("praise")'

# R interactive-visualisation + Shinylive packages — htmlwidgets for "fancy"
# interactive output that still publishes to STATIC hosting (GitHub Pages):
# plotly + leaflet (charts/maps), DT (interactive tables), crosstalk (client-
# side linking/filtering, no server); plus shiny + shinylive, which compile a
# Shiny app to WebAssembly (webR) so it too runs on a static host. pak via P3M
# Linux binaries — fast (~16 s, ~70 MB). (Python equivalents — plotly/altair/
# folium/itables/shiny/shinylive — are in requirements.lock.)
RUN R -q -e 'pak::pkg_install(c("plotly", "leaflet", "DT", "crosstalk", "shiny", "shinylive"))' \
    && R --vanilla -e 'for (p in c("plotly","leaflet","DT","crosstalk","shiny","shinylive")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Mapping / census stack — NYT-style tract maps (dot-density, choropleths):
# sf (vector geodata; links against the GDAL/PROJ/GEOS/udunits system libs
# baked above) and tidycensus (ACS/decennial data + geometry in one call;
# pulls in tigris for TIGER shapefiles). Students need a free Census API key
# for live tidycensus queries. P3M Linux binaries, so this is fast. The
# interactive path needs nothing more: leaflet (above) draws sf objects, and
# free CARTO basemap tiles substitute for Mapbox.
#
# Plus the rest of the Kyle Walker toolkit:
#  - mapgl:     MapLibre/Mapbox GL htmlwidgets — WebGL vector maps (the NYT
#               look) with NO token via maplibre() + CARTO styles; publishes
#               static to GitHub Pages like every other htmlwidget here.
#  - crsuggest: suggests the right projected CRS for a dataset — the one-
#               function answer to the #1 beginner mapping confusion.
#  - idbr:      Census International Data Base (population pyramids, country
#               time series); uses the same Census API key as tidycensus.
# Deliberately NOT mapboxapi: it requires a per-student Mapbox account/token.
RUN R -q -e 'pak::pkg_install(c("sf", "tidycensus", "mapgl", "crsuggest", "idbr"))' \
    && R --vanilla -e 'for (p in c("sf","tidycensus","tigris","mapgl","crsuggest","idbr")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)' \
    && R --vanilla -e 'library(sf); p <- st_sfc(st_polygon(list(rbind(c(0,0), c(1,0), c(1,1), c(0,1), c(0,0)))), crs = 4326); pts <- st_sample(p, 10); stopifnot(length(pts) == 10); cat("sf geometry ops OK\n")'

# Images + animation (since v1.1.6). The standard R toolkit for working with
# pictures and for animating plots; system libs are in the apt block above.
#   - magick:     ImageMagick bindings — read/write/resize/annotate/compose
#                 any raster format; the hub everything else here plugs into
#   - rsvg, webp, png, jpeg: format readers/writers magick and ggplot2
#                 helpers lean on (rsvg renders SVG to raster)
#   - ggimage, ggpattern, ggfx: pictures, image fills, and filters (glow,
#                 shadow, blur) INSIDE ggplot2
#   - gganimate:  animate a ggplot by a time/state variable; rendered by
#   - gifski (GIF) and av (MP4 via ffmpeg) — both renderers, so students
#                 can pick the format their target (web page vs. slide) needs
#   - transformr: shape tweening for gganimate on polygons/paths/sf
#   - camcorder:  records every plot made in a session into a GIF of the
#                 build-up — a teaching device as much as an output
# Deliberately NOT imager (needs X11; overlaps magick). P3M Linux binaries.
# (Python equivalents — Pillow, scikit-image, imageio(+ffmpeg) — are in
# requirements.lock; the ffmpeg CLI is apt-installed for matplotlib.)
RUN R -q -e 'pak::pkg_install(c("magick", "rsvg", "webp", "png", "jpeg", "ggimage", "ggpattern", "ggfx", "gganimate", "gifski", "av", "transformr", "camcorder"))' \
    && R --vanilla -e 'for (p in c("magick","rsvg","webp","png","jpeg","ggimage","ggpattern","ggfx","gganimate","gifski","av","transformr","camcorder")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Smoke test: a PNG round trip + an SVG render through the real ImageMagick
# and librsvg links (a load check passes even when the system lib is absent
# at the version the binary wants — the first image_read is what fails).
RUN R --vanilla -e 'library(magick); f <- tempfile(fileext = ".png"); image_write(image_blank(20, 10, "red"), f); i <- image_info(image_read(f)); stopifnot(i$width == 20, i$height == 10); s <- tempfile(fileext = ".png"); rsvg::rsvg_png(charToRaw("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\"><rect width=\"8\" height=\"8\"/></svg>"), s); stopifnot(file.size(s) > 0); cat("magick + rsvg OK\n")'

# Smoke test: gganimate end to end through BOTH renderers — a tiny GIF via
# gifski and a tiny MP4 via av. This is the student path (animate() +
# anim_save()) and the only proof the ffmpeg libraries actually link.
RUN R --vanilla -e 'suppressPackageStartupMessages({library(ggplot2); library(gganimate)}); d <- data.frame(x = rep(1:3, 2), y = c(1, 2, 3, 3, 2, 1), t = rep(1:2, each = 3)); p <- ggplot(d, aes(x, y)) + geom_point() + transition_states(t); g <- tempfile(fileext = ".gif"); anim_save(g, animate(p, nframes = 4, fps = 2, width = 100, height = 100, renderer = gifski_renderer())); stopifnot(file.size(g) > 0); m <- tempfile(fileext = ".mp4"); anim_save(m, animate(p, nframes = 4, fps = 2, width = 100, height = 100, renderer = av_renderer())); stopifnot(file.size(m) > 0); cat("gganimate gif (gifski) + mp4 (av) OK\n")'

USER root

# ── Python data-science stack ────────────────────────────────────────────────
# Lets students do data science in Python too, not just R: numpy/pandas
# (wrangling), matplotlib/seaborn (plots), scikit-learn (ML), statsmodels
# (regression/inference — the lm() analog), and jupyter/ipykernel (notebooks;
# also what Quarto's Python engine and the VS Code Jupyter extension drive).
# We pin the full dependency tree in requirements.lock (generated from
# requirements.txt via `uv pip compile`); edit the .txt and recompile to
# bump versions.
#
# Installed with uv (Astral's fast resolver/installer) into a venv at /opt/venv:
#   --seed        → put pip/setuptools/wheel IN the venv, so students can plain
#                   `pip install` more packages (uv venvs omit pip by default).
#   --python /usr/bin/python3 → use the system CPython, NOT a uv-managed
#                   download, so it's a normal, predictable interpreter.
#   chgrp staff + g+w → make the venv group-writable (rstudio is in staff), the
#                   same treatment R's site-library gets, so a student's
#                   `pip install` actually has somewhere to write.
# /opt/venv goes first on PATH, so `python`/`pip`/`jupyter` are the venv's.
# Quarto runs Python via the jupyter engine (ipykernel) — no reticulate needed.
# We still set RETICULATE_PYTHON so that IF someone installs R's reticulate
# (not baked in) it bridges to this same venv rather than a separate Python.
# uv's own binary is copied from its official pinned image (pinned, unlike agy).
COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uv /usr/local/bin/uv
COPY requirements.lock /tmp/requirements.lock
COPY requirements.txt /tmp/requirements.txt

# Lock-staleness guard: every top-level package in requirements.txt must appear
# in the lock, so editing the .txt and forgetting to re-run `uv pip compile`
# fails the build instead of silently shipping a stale lock. Presence-only (no
# version comparison), so it never false-fails when PyPI publishes new
# transitive versions.
RUN set -eu; \
    while IFS= read -r line; do \
        case "$line" in ''|\#*) continue ;; esac; \
        pkg="${line%%[=<>!~ ]*}"; \
        grep -qiE "^${pkg}==" /tmp/requirements.lock \
          || { echo "requirements.lock is STALE: '${pkg}' is in requirements.txt but not the lock — run: uv pip compile requirements.txt -o requirements.lock" >&2; exit 1; }; \
    done < /tmp/requirements.txt

RUN uv venv --seed --python /usr/bin/python3 /opt/venv \
    && uv pip install --python /opt/venv/bin/python --no-cache -r /tmp/requirements.lock \
    && /opt/venv/bin/python -m ipykernel install --prefix /usr/local \
         --name python3 --display-name "Python (data science)" \
    && chgrp -R staff /opt/venv \
    && chmod -R g+w /opt/venv \
    && rm /tmp/requirements.lock /tmp/requirements.txt
ENV PATH=/opt/venv/bin:$PATH \
    RETICULATE_PYTHON=/opt/venv/bin/python

# Smoke test 1: the whole stack must import (catches a bad lock / ABI break at
# build time instead of at a student's first import).
RUN python -c "import numpy, pandas, matplotlib, seaborn, sklearn, statsmodels, ipykernel, plotly, altair, folium, itables, shiny, shinylive, PIL, skimage, imageio, imageio_ffmpeg; print('py-ds stack OK')"

# Smoke test 1b: images + animation end to end — a Pillow round trip, and a
# matplotlib animation saved as GIF (PillowWriter) and MP4 (FFMpegWriter,
# which shells out to the apt-installed ffmpeg CLI). This is the student
# path; an import check cannot tell whether ffmpeg is actually on PATH.
RUN python - <<'PY'
import os, tempfile
import numpy as np
from PIL import Image
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation, PillowWriter, FFMpegWriter
d = tempfile.mkdtemp()
p = os.path.join(d, "a.png"); Image.new("RGB", (20, 10), "red").save(p)
assert Image.open(p).size == (20, 10)
fig, ax = plt.subplots(figsize=(1, 1)); ln, = ax.plot([], [])
anim = FuncAnimation(fig, lambda i: ln.set_data([0, i], [0, i]), frames=3)
g = os.path.join(d, "a.gif"); anim.save(g, writer=PillowWriter(fps=2)); assert os.path.getsize(g) > 0
m = os.path.join(d, "a.mp4"); anim.save(m, writer=FFMpegWriter(fps=2)); assert os.path.getsize(m) > 0
print("Pillow + matplotlib gif/mp4 OK")
PY

# Smoke test 2: a non-root student (rstudio, in staff) can pip-install into the
# venv — the Python analog of the R 'praise' test above. --seed gave the venv a
# pip; the group-writable perms let rstudio use it.
RUN su rstudio -c "/opt/venv/bin/pip install --no-cache-dir --quiet cowsay" \
    && /opt/venv/bin/python -c "import cowsay; print('rstudio-can-install OK')" \
    && /opt/venv/bin/pip uninstall -y --quiet cowsay

# Smoke test 3: Quarto renders a Python chunk through the jupyter engine,
# driven entirely from the CLI. This is the student-facing Python path now
# that codespace-starter dropped the VS Code Python extensions (2026-08-20,
# to thin the Activity Bar): the claim was that nothing students actually do
# depends on those extensions, and this test is that claim made falsifiable.
# The chunk writes a file rather than checking rendered HTML, so the test
# proves the chunk EXECUTED (with pandas importable) rather than merely that
# quarto emitted a document. Runs as rstudio, like a student. NOT covered,
# and deliberately gone with the extensions: the editor-side .ipynb UI, cell
# run-buttons, and Python IntelliSense.
#
# PATH is passed through explicitly because `su rstudio -c` RESETS it on
# Debian (login.defs), dropping the /opt/venv/bin that this image's ENV puts
# first — Quarto then falls back to the system python3, which has no jupyter
# or yaml, and the render dies with "Jupyter is not available in this Python
# installation" (build 32544605003). Students are unaffected: their terminals
# inherit the container ENV. Same reason the pip test above uses an absolute
# /opt/venv/bin path. The outer shell expands $PATH here, so the literal
# venv-first path is what reaches rstudio.
RUN mkdir -p /tmp/pysmoke \
 && printf '%s\n' \
      '---' \
      'title: py-engine smoke' \
      'format: html' \
      '---' \
      '' \
      '```{python}' \
      'import pandas as pd' \
      'open("/tmp/pysmoke/chunk-ran", "w").write(str(int(pd.Series([1, 2, 3]).sum())))' \
      '```' \
      > /tmp/pysmoke/smoke.qmd \
 && chown -R rstudio /tmp/pysmoke \
 && su rstudio -c "cd /tmp/pysmoke && PATH='$PATH' quarto render smoke.qmd --to html" \
 && test -f /tmp/pysmoke/smoke.html \
 && grep -qx '6' /tmp/pysmoke/chunk-ran \
 && echo "quarto python-chunk render OK" \
 && rm -rf /tmp/pysmoke
# ─────────────────────────────────────────────────────────────────────────────

# ── Observable Framework ─────────────────────────────────────────────────────
# Observable's open-source static-site generator for interactive data apps and
# dashboards (JavaScript front-end + any-language back-end). Adds the
# `observable` CLI (`observable create`, `observable preview`, `observable
# build`). Node is already present (installed above for the AI CLIs); ~84 MB.
#
# NOTE: interactive Observable charts INSIDE a Quarto document need NOTHING
# extra — Quarto's bundled `{ojs}` cells already render Observable Plot / OJS
# (build-test verified). Framework is only for standalone data-app projects.
# The `observable --version` call is the smoke test (fails the build if broken).
RUN npm install -g @observablehq/framework@1.13.4 && observable --version
# ─────────────────────────────────────────────────────────────────────────────

# ── VS Code extensions, baked (ours + the launcher's whole list) ─────────────
# Pre-extracted into the VS Code server's extensions dir, so the editor loads
# them from the very first window paint and installs NOTHING at attach.
#  - Why bake rather than list them in devcontainer.json: that list installs
#    from the Microsoft Marketplace at attach time — a network round trip on
#    every launch, a ~30 s window where the Activity Bar is incomplete and an
#    R terminal does not exist yet while the banner already says READY, and
#    (for ours) a Marketplace that we don't publish to. Open VSX has all of
#    them. codespace-starter keeps its `extensions` list as well, pinned to
#    the same versions: VS Code sees them installed and skips the install.
#  - Why not a vsix install at attach time (tried, in welcome.sh): an
#    extension installed into an already-running window doesn't surface its
#    Activity Bar icon until the window reloads — bad first-run UX.
# A .vsix is a zip with the payload under extension/; the dir name follows
# VS Code's publisher.name-version convention (lowercased), which its scanner
# picks up. NOTE: deliberate exception to "keep the image editor-agnostic" —
# non-VS-Code consumers simply ignore ~/.vscode-remote. To ship a new version
# of ours: publish to Open VSX by hand (`ovsx publish`), bump RT_EXT_VERSION
# (top of file), release. For the others: bump the ARG, release, and bump the
# matching pin in codespace-starter's extensions list in the same cycle.
# The vscode-R .vsix is kept at /tmp/vscode-r-ext for the sess bake below.
RUN set -eux; \
    for spec in \
        "PPBDS/vscode-r-tutorials/${RT_EXT_VERSION}" \
        "REditorSupport/r/${VSCODE_R_VERSION}" \
        "REditorSupport/r-syntax/${R_SYNTAX_EXT_VERSION}" \
        "quarto/quarto/${QUARTO_EXT_VERSION}" \
        "ritwickdey/LiveServer/${LIVESERVER_EXT_VERSION}" \
        "tomoki1207/pdf/${PDF_EXT_VERSION}" \
        "mechatroner/rainbow-csv/${RAINBOW_CSV_EXT_VERSION}"; \
    do \
        pub="${spec%%/*}"; rest="${spec#*/}"; name="${rest%%/*}"; ver="${rest#*/}"; \
        url="https://open-vsx.org/api/${pub}/${name}/${ver}/file/${pub}.${name}-${ver}.vsix"; \
        dest="/home/rstudio/.vscode-remote/extensions/$(printf '%s.%s-%s' "$pub" "$name" "$ver" | tr '[:upper:]' '[:lower:]')"; \
        curl -fsSL -o /tmp/ext.vsix "$url"; \
        rm -rf /tmp/ext; python3 -m zipfile -e /tmp/ext.vsix /tmp/ext; \
        mkdir -p "$dest"; cp -R /tmp/ext/extension/. "$dest/"; \
        test -f "$dest/package.json"; \
        python3 -c "import json, sys; v = json.load(open('$dest/package.json'))['version']; sys.exit(0 if v == '$ver' else ('unexpected version for $pub.$name: ' + v))"; \
        if [ "$pub.$name" = "REditorSupport.r" ]; then rm -rf /tmp/vscode-r-ext; mv /tmp/ext /tmp/vscode-r-ext; fi; \
        rm -rf /tmp/ext.vsix /tmp/ext; \
        echo "EXTENSION $pub.$name $ver OK"; \
    done; \
    chown -R rstudio:rstudio /home/rstudio/.vscode-remote; \
    ls /home/rstudio/.vscode-remote/extensions
# ─────────────────────────────────────────────────────────────────────────────

# ── sess: vscode-R 3.x's session bridge, baked from the SAME .vsix ───────────
# vscode-R >= 3.0 talks to an R session through its bundled `sess` R package
# (not on CRAN; r-universe has it, but at whatever version is current). At
# every R-terminal start the extension compares the installed sess version
# with the one in its own .vsix and, if installed < bundled, prompts "install
# sess?" (src/util.ts promptToInstallSessPackage) — a prompt students must
# never see. Installing from the .vsix's own sess/ directory makes the two
# versions identical by construction. Imports (processx, later, jsonlite,
# rstudioapi) come from P3M first so R CMD INSTALL never reaches for CRAN.
# Installed as rstudio into site-library like every other R package here.
USER rstudio
RUN R -q -e 'pak::pkg_install(c("processx", "later", "jsonlite", "rstudioapi"))' \
 && R CMD INSTALL /tmp/vscode-r-ext/extension/sess \
 && R --vanilla -e 'stopifnot(requireNamespace("sess", quietly = TRUE)); b <- read.dcf("/tmp/vscode-r-ext/extension/sess/DESCRIPTION", "Version")[[1]]; i <- as.character(utils::packageVersion("sess")); if (utils::compareVersion(i, b) < 0) stop("baked sess ", i, " is OLDER than the bundled ", b, " — the extension would prompt to install"); cat("SESS", i, "OK (bundled", b, ")\n")' \
 && R --vanilla -e 'stopifnot(requireNamespace("httpgd", quietly = TRUE)); cat("httpgd (r.plot.backend) OK\n")'
USER root
RUN rm -rf /tmp/vscode-r-ext
# ─────────────────────────────────────────────────────────────────────────────

# NOTE — no Workspace Trust pre-seed. v1.1.5 baked a user settings.json with
# `security.workspace.trust.enabled: false` here; it was REMOVED in v1.1.6
# because it never worked: every security.workspace.trust.* setting is
# application-scoped, read only from the Codespaces web client's browser-side
# user settings (vscode workspace.contribution.ts), so neither the image, nor
# devcontainer.json, nor a script in the container can suppress the "Do you
# trust the authors?" modal. (The 2026-08-22 "proof" was a folder already
# trusted by a click, then reloaded.) Students click "Trust Folder &
# Continue". Do not re-add anything on this path.

# ── First-run terminal notice: EMPTY on purpose ─────────────────────────────
# The devcontainers base prints this file once, in the first terminal of a
# new Codespace (its bash.bashrc hook tests only that the file EXISTS; with
# no file it falls back to GitHub's stock "Welcome to Codespaces" blurb —
# hence an empty file rather than none). Until v1.1.6 it held a "setup is
# still finishing, wait for the banner" notice that bridged the gap before
# codespace-starter's postAttach terminal appeared. That gap is gone: the
# ready banner now prints from ~/.bashrc in this same first terminal, the
# instant it opens, so any text here would just sit above it as noise.
RUN : > /usr/local/etc/vscode-dev-containers/first-run-notice.txt

# Smoke test: the file exists (so the stock blurb stays suppressed) and is
# EMPTY (so nothing prints above the banner).
RUN test -f /usr/local/etc/vscode-dev-containers/first-run-notice.txt \
    && test ! -s /usr/local/etc/vscode-dev-containers/first-run-notice.txt \
    && echo "FIRST-RUN NOTICE (empty) OK"
# ─────────────────────────────────────────────────────────────────────────────

# ── `quarto create` never opens a duplicate editor tab ───────────────────────
# `quarto create` auto-opens the new project in the editor it is running
# inside: it detects VS Code purely from TERM_PROGRAM == "vscode" and runs
# `code <path>` with no reuse flag — which, in the Codespaces web client,
# opens a SECOND browser tab of the same Codespace (quarto-cli create/cmd.ts
# resolveEditor; verified 2026-09-17). `--no-open` prevents it. A blanket
# alias is wrong (`render`/`preview`/`publish` reject unknown options), so a
# bash FUNCTION appends `--no-open` only to `create`, and only when none of
# `--open`, `--open=<editor>` or `--no-open` was given (Copilot, PR #35). Interactive shells only (/etc/bash.bashrc
# is read by interactive non-login shells, i.e. VS Code terminals;
# /etc/profile.d is NOT) — the Quarto VS Code extension execs the binary by
# path and is unaffected. The tutorials show the flag explicitly anyway, so
# this is a safety net, not magic they depend on.
RUN cat >> /etc/bash.bashrc <<'EOF'

# PPBDS: keep `quarto create` from opening a duplicate editor tab in Codespaces.
quarto() {
    if [ "${1-}" = "create" ]; then
        for a in "$@"; do
            case "$a" in --open|--open=*|--no-open) command quarto "$@"; return ;; esac
        done
        command quarto "$@" --no-open
    else
        command quarto "$@"
    fi
}
EOF

# Smoke test: an interactive shell sees the function, and it forwards.
RUN bash -ic 'type quarto | grep -q "is a function" && quarto --version' \
    && echo "QUARTO CREATE SHIM OK"
# ─────────────────────────────────────────────────────────────────────────────

# ── devcontainer.metadata label: inherited extension lists REMOVED ──────────
# The rocker base image carries an OCI label, `devcontainer.metadata`, that
# the devcontainer tooling (and so the Codespaces client) MERGES into the
# effective devcontainer config at attach — including `customizations.vscode.
# extensions`. Inherited as-is, that label asked for two extensions on EVERY
# account, students included (found 2026-10-05, incognito as davekane-student):
#   - `RDebugger.r-debugger` (rocker's own devcontainer config): with vscode-R
#     3.x present it triggers the "R Debugger still registers the legacy
#     r.rpath.<platform> setting" warning once per Codespace — for everyone.
#   - `REditorSupport.r` UNPINNED (rocker's r-rig feature): a standing request
#     for the Marketplace's latest vscode-R, competing with codespace-starter's
#     version pin — how a Codespace went 2.8.8 → 3.0.1 uninvited that morning.
# We bake every extension we want (see the extension block above) and
# codespace-starter declares the pins, so the label must contribute NONE.
# A LABEL here REPLACES the inherited value. What is kept: the feature ids
# (informational) and `remoteUser: rstudio` — that one is load-bearing, it is
# what makes the Codespace run as rstudio. Dropped besides the extensions:
# rocker's `r.rterm.linux: …/radian` (deprecated key, radian is not even
# installed), `r.plot.useHttpgd` and `r.bracketedPaste` (the launcher sets
# the 3.0 equivalents), and the r-rig `[r]` wordSeparators (moved to the
# launcher's settings, where it is visible). build.yml verifies the pushed
# image's label after every build. If the base image ever adds metadata we
# want, add it here deliberately — never by inheritance.
LABEL devcontainer.metadata="[{\"id\":\"ghcr.io/devcontainers/features/common-utils:2\"},{\"id\":\"ghcr.io/rocker-org/devcontainer-features/r-rig:1\"},{\"id\":\"ghcr.io/rocker-org/devcontainer-features/r-packages:1\"},{\"remoteUser\":\"rstudio\"}]"
# ─────────────────────────────────────────────────────────────────────────────

# ── Image-wide smoke tests ───────────────────────────────────────────────────
# R version guard: the base digest encodes the R version; this fails the
# build if a digest bump ever changes the R minor version unnoticed (R minor
# bumps break package ABI image-wide, so they must be deliberate migrations).
RUN R --vanilla -e 'v <- getRversion(); stopifnot(v >= "4.6.0", v < "4.7.0"); cat("R", as.character(v), "OK\n")'

# R smoke test: foundational packages must load. Catches binary-ABI
# mismatches at build time instead of at Codespace-launch time.
# --vanilla skips Rprofile so this isolates the package-load path itself.
RUN R --vanilla -e 'for (p in c("pak", "httpgd")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Modeling smoke test 1: tidymodels, bonsai, every engine, and brms must load.
RUN R --vanilla -e 'for (p in c("tidymodels", "bonsai", "xgboost", "lightgbm", "randomForest", "ranger", "glmnet", "brms", "catboost")) if (!requireNamespace(p, quietly = TRUE)) stop("modeling smoke test failed to load: ", p)'

# Inference/presentation smoke test: the primer book+tutorial packages must load.
RUN R --vanilla -e 'for (p in c("gt", "marginaleffects", "patchwork", "easystats")) if (!requireNamespace(p, quietly = TRUE)) stop("inference/presentation smoke test failed to load: ", p)'

# Modeling smoke test 2: CatBoost end-to-end THROUGH tidymodels/bonsai — fit a
# tiny model and predict, not just load the package. Since catboost is installed
# with --no-test-load, this is the real proof the binary + engine binding work.
RUN R --vanilla -e 'suppressPackageStartupMessages({library(tidymodels); library(bonsai)}); m <- boost_tree(trees = 5, mode = "regression") |> set_engine("catboost") |> fit(mpg ~ ., data = mtcars); stopifnot(nrow(predict(m, mtcars)) == nrow(mtcars)); cat("catboost + bonsai end-to-end OK\n")'

# Modeling smoke test 3: brms end-to-end — fit a trivial model so the build
# actually COMPILES a Stan program with the image's toolchain. A load check
# wouldn't catch a broken Stan/compiler config; this does. chains/iter are tiny
# since we only care that compilation + sampling run, not about the estimates.
RUN R --vanilla -e 'fit <- brms::brm(mpg ~ wt, data = mtcars, chains = 1, iter = 100, refresh = 0, silent = 2); stopifnot(inherits(fit, "brmsfit")); cat("brms + Stan end-to-end OK\n")'

# CLI smoke test: every shell tool must be on PATH and runnable.
RUN claude --version && codex --version && agy --version && grok --version && aider --version

# ── End-to-end authoring smoke tests ─────────────────────────────────────────
# These run last, once R + Python + Quarto are all in place, so they exercise
# the actual student authoring path (not just that packages load). We render an
# R doc and a Python doc SEPARATELY — that's how students work (one language per
# doc), and it covers BOTH Quarto engines without needing reticulate: an R doc
# uses the knitr engine, a Python-only doc uses the jupyter engine (the venv's
# ipykernel). NOTE: these are build-time and headless, so they cannot catch VS
# Code / extension runtime issues (e.g. the Python extension activating the venv
# in the R terminal) — that class needs a manual "launch a Codespace and run a
# tutorial" check.
#
# (a) An R-only Quarto doc must render to HTML (knitr engine).
RUN set -eux; \
    d="$(mktemp -d)"; cd "$d"; \
    printf '%s\n' '---' 'title: r' 'format: html' '---' '' \
      '```{r}' 'summary(cars$speed)' '```' > r.qmd; \
    quarto render r.qmd --to html; test -s r.html; echo "QUARTO-R OK"; \
    cd /; rm -rf "$d"

# (b) A Python-only Quarto doc must render to HTML (jupyter engine → venv kernel).
RUN set -eux; \
    d="$(mktemp -d)"; cd "$d"; \
    printf '%s\n' '---' 'title: py' 'format: html' 'jupyter: python3' '---' '' \
      '```{python}' 'import pandas as pd' 'pd.DataFrame({"a": [1, 2]}).describe()' '```' > p.qmd; \
    quarto render p.qmd --to html; test -s p.html; echo "QUARTO-PY OK"; \
    cd /; rm -rf "$d"

# (c) The course tutorials must be discoverable (catches a broken tutorial pkg).
RUN R --vanilla -e 'ts <- learnr::available_tutorials("tutorial.helpers"); if (!("getting-started" %in% ts$name)) stop("getting-started tutorial not found"); cat("TUTORIALS OK:", paste(ts$name, collapse = ", "), "\n")'

# (d) The R Tutorials extension's own listing call must work: it runs exactly
# this (src/extension.ts) to fill the Tutorials panel. A learnr2 that loads
# but cannot list vscode.tutorials means an empty panel for every student.
RUN R --vanilla -e 'ts <- learnr2::available_tutorials(package = "vscode.tutorials"); stopifnot(is.data.frame(ts), nrow(ts) > 0); cat("LEARNR2 LISTING OK:", nrow(ts), "vscode.tutorials tutorials\n")'
# ─────────────────────────────────────────────────────────────────────────────

# Locale (en_US.UTF-8) and timezone (Etc/UTC) are inherited from the rocker base.
