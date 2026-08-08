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

# Pinned by digest. The :4.5 tag floats as Rocker patches the image; the
# digest freezes us at a known build. To bump: pull :4.5 fresh, copy the
# new digest in, commit deliberately. Do not switch to :4.5 unpinned.
# R version note: this base is R 4.5 (rocker's newest devcontainer image).
# R 4.6.0 shipped 2026-04-24 but rocker has not yet published a :4.6
# devcontainer image; revisit once it exists and its P3M binaries settle.
FROM ghcr.io/rocker-org/devcontainer/tidyverse:4.5@sha256:289c5d02d8115aa209f4a8a49ee9378dccbf623897eed9cc46c87dfbbca9015b

ARG QUARTO_VERSION=1.10.18
ARG ARF_VERSION=0.4.5
ARG NODE_MAJOR=24

# AI CLI versions. Pinned so builds are reproducible and the baked version
# doesn't silently drift behind the registry. Bump deliberately, like
# Quarto/arf. (Antigravity CLI is the exception — its installer offers no
# version pin, so `agy` floats; see the agy install block below.)
ARG CLAUDE_CODE_VERSION=2.1.226
ARG CODEX_VERSION=0.147.0
ARG GROK_VERSION=1.0.0
# aider is pip-distributed; pinned like the npm CLIs (it floated unpinned
# until v1.0.8 — the one exception with a pin mechanism available).
ARG AIDER_VERSION=0.86.2

# PPBDS.vscode-r-tutorials extension version, baked from Open VSX (see the
# extension block near the bottom). Bump deliberately; a bump is an image
# release.
ARG RT_EXT_VERSION=1.0.0

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
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI. Official install method per the gh docs.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

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

# pak: fast parallel R package installer, used for every R install below.
RUN R -q -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))'

# tidymodels + a set of modeling engines. All of these are pulled from the
# CURRENT P3M snapshot (overriding rocker's frozen one) so we get versions
# recent enough for the CatBoost engine (parsnip >= 1.4.0, bonsai >= 0.4.1)
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
RUN R -q -e 'options(repos = c(P3M = "https://packagemanager.posit.co/cran/__linux__/noble/latest")); pak::pkg_install(c("tidymodels", "bonsai", "remotes", "xgboost", "lightgbm", "randomForest", "ranger", "glmnet", "brms", "BH", "RcppEigen", "RcppParallel"))' \
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
RUN R -q -e 'options(repos = c(P3M = "https://packagemanager.posit.co/cran/__linux__/noble/latest")); pak::pkg_install(c("gt", "marginaleffects", "patchwork", "easystats"))'

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
ARG COURSE_PKG_REFRESH=2026-08-08
RUN echo "course-package refresh: ${COURSE_PKG_REFRESH}" \
 && R -q -e 'pak::pkg_install(c( \
        "PPBDS/tutorial.helpers", \
        "PPBDS/vscode.tutorials", \
        "PPBDS/misc.tutorials", \
        "PPBDS/primer.tutorials" \
    ), upgrade = TRUE, dependencies = TRUE)'

# Smoke test 1: every baked-in package and the learnr/knitr/rmarkdown
# chain must all load. The original learnr/xfun ABI mismatch failure
# would have been caught here at build time.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "misc.tutorials", "primer.tutorials", "learnr", "knitr", "rmarkdown")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

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
RUN python -c "import numpy, pandas, matplotlib, seaborn, sklearn, statsmodels, ipykernel, plotly, altair, folium, itables, shiny, shinylive; print('py-ds stack OK')"

# Smoke test 2: a non-root student (rstudio, in staff) can pip-install into the
# venv — the Python analog of the R 'praise' test above. --seed gave the venv a
# pip; the group-writable perms let rstudio use it.
RUN su rstudio -c "/opt/venv/bin/pip install --no-cache-dir --quiet cowsay" \
    && /opt/venv/bin/python -c "import cowsay; print('rstudio-can-install OK')" \
    && /opt/venv/bin/pip uninstall -y --quiet cowsay
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

# ── R Tutorials VS Code extension (PPBDS.vscode-r-tutorials) ─────────────────
# Baked into the image, pre-extracted into the VS Code server's extensions
# dir, so the editor loads it from the very first window paint.
#  - Why not devcontainer.json's "extensions" list: that list only installs
#    from the Microsoft Marketplace, and we publish this extension to Open
#    VSX only (Marketplace publishing is too painful — David, 2026-07).
#  - Why not a vsix install at attach time (tried, in welcome.sh): an
#    extension installed into an already-running window doesn't surface its
#    Activity Bar icon until the window reloads — bad first-run UX.
# A .vsix is a zip with the payload under extension/; the dir name follows
# VS Code's publisher.name-version convention, which its scanner picks up.
# NOTE: deliberate exception to "keep the image editor-agnostic" — non-VS-Code
# consumers simply ignore ~/.vscode-remote. To ship a new extension version:
# publish to Open VSX, bump RT_EXT_VERSION (top of file), release the image.
RUN set -eux; \
    url="https://open-vsx.org/api/PPBDS/vscode-r-tutorials/${RT_EXT_VERSION}/file/PPBDS.vscode-r-tutorials-${RT_EXT_VERSION}.vsix"; \
    dest="/home/rstudio/.vscode-remote/extensions/ppbds.vscode-r-tutorials-${RT_EXT_VERSION}"; \
    curl -fsSL -o /tmp/rt.vsix "$url"; \
    python3 -m zipfile -e /tmp/rt.vsix /tmp/rt-ext; \
    mkdir -p "$dest"; \
    cp -R /tmp/rt-ext/extension/. "$dest/"; \
    chown -R rstudio:rstudio /home/rstudio/.vscode-remote; \
    rm -rf /tmp/rt.vsix /tmp/rt-ext; \
    test -f "$dest/package.json"; \
    python3 -c "import json, sys; v = json.load(open('$dest/package.json'))['version']; sys.exit(0 if v == '$RT_EXT_VERSION' else ('unexpected extension version: ' + v))"; \
    echo "R-TUTORIALS EXTENSION ${RT_EXT_VERSION} OK"
# ─────────────────────────────────────────────────────────────────────────────

# ── First-run terminal notice ────────────────────────────────────────────────
# The text the devcontainers base prints in the FIRST terminal of a new
# Codespace (via its bash.bashrc hook; shown once per codespace, tracked by a
# marker in ~/.config/vscode-dev-containers/). We replace the stock "Welcome
# to Codespaces" blurb because it fires at the START of a ~30 s silent gap —
# extensions installing, postAttach still queued — during which students
# wonder if setup is done and start typing. This text bridges the gap: it
# says setup is still running and names the exact banner (welcome.sh's
# "YOUR CODESPACE IS READY", from codespace-starter) that means "go". The
# wording deliberately tolerates the fast case where the banner is already
# visible. Keep the banner text here in sync with welcome.sh.
COPY <<'NOTICE' /usr/local/etc/vscode-dev-containers/first-run-notice.txt
👋 Welcome! This is your data-science workshop for Preceptor's Primer.

⏳ SETUP IS STILL FINISHING — usually about half a minute more.

   Please don't type anything yet. Setup is done only when a banner
   saying "✅  YOUR CODESPACE IS READY" appears below, and that banner
   will tell you what to do next. (Already see it? Then you're all set.)
NOTICE

# Smoke test: the notice is in place and names the ready banner.
RUN test -s /usr/local/etc/vscode-dev-containers/first-run-notice.txt \
    && grep -q "YOUR CODESPACE IS READY" /usr/local/etc/vscode-dev-containers/first-run-notice.txt \
    && echo "FIRST-RUN NOTICE OK"
# ─────────────────────────────────────────────────────────────────────────────

# ── Image-wide smoke tests ───────────────────────────────────────────────────
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
# ─────────────────────────────────────────────────────────────────────────────

# Locale (en_US.UTF-8) and timezone (Etc/UTC) are inherited from the rocker base.
