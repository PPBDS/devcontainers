# syntax=docker/dockerfile:1.7

# Pinned by digest. The :4.5 tag floats as Rocker patches the image; the
# digest freezes us at a known build. To bump: pull :4.5 fresh, copy the
# new digest in, commit deliberately. Do not switch to :4.5 unpinned.
# R version note: this base is R 4.5 (rocker's newest devcontainer image).
# R 4.6.0 shipped 2026-04-24 but rocker has not yet published a :4.6
# devcontainer image; revisit once it exists and its P3M binaries settle.
FROM ghcr.io/rocker-org/devcontainer/tidyverse:4.5@sha256:289c5d02d8115aa209f4a8a49ee9378dccbf623897eed9cc46c87dfbbca9015b

ARG QUARTO_VERSION=1.9.38
ARG ARF_VERSION=0.3.4
ARG NODE_MAJOR=22

# AI CLI versions. Pinned so builds are reproducible and the baked version
# doesn't silently drift behind the registry. Bump deliberately, like
# Quarto/arf. (Antigravity CLI is the exception — its installer offers no
# version pin, so `agy` floats; see the agy install block below.)
ARG CLAUDE_CODE_VERSION=2.1.181
ARG CODEX_VERSION=0.141.0

# System libraries needed by both downstream images.
#  - Geospatial: sf, terra, etc.
#  - text shaping libs: ragg / textshaping (modern ggplot2 graphics)
#  - cmake: build tool for source packages like fs (pulled in by primer.tutorials)
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
#   - aider   (multi-provider)           — key-only: DeepSeek/OpenRouter/OpenAI/Anthropic
#
# NOTE: Google's Gemini CLI was REMOVED. Google EOL'd the consumer Gemini CLI
# on 2026-06-18 — the free/sign-in path stopped serving requests — and pushed
# everyone to Antigravity. The Google slot is now the Antigravity CLI (`agy`,
# installed further below via Google's curl installer, alongside arf).
#
# Node hosts the npm-distributed CLIs (claude, codex). We install from
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
    && pipx install aider-chat

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
# changes, only base/Dockerfile needs updating, not every consumer.
RUN ln -s /home/rstudio/.cargo/bin/arf /usr/local/bin/arf \
    && ln -s /home/rstudio/.local/bin/agy /usr/local/bin/agy

# pak: fast parallel R package installer. Used by both downstream images,
# so install once at the base layer.
RUN R -q -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))'

# tidymodels + a set of modeling engines, shared by dev and student. All of
# these are pulled from the CURRENT P3M snapshot (overriding rocker's frozen
# one) so we get versions recent enough for the CatBoost engine (parsnip
# >= 1.4.0, bonsai >= 0.4.1) and current everything else. None of the engine
# packages ship inside the tidymodels meta-package — parsnip only provides the
# interface, so each backend is installed explicitly here:
#   - tidymodels  : the modeling framework (parsnip/recipes/rsample/tune/yardstick/…)
#   - bonsai      : parsnip bridge for the lightgbm AND catboost engines
#   - xgboost, lightgbm, randomForest, ranger, glmnet : tree/regularized engines
#   - brms        : Bayesian regression via Stan — heavy (pulls rstan/StanHeaders);
#                   compiles models at runtime using the rocker C++ toolchain
#   - BH, RcppEigen, RcppParallel : the Boost / Eigen / TBB C++ headers rstan
#                   needs to COMPILE Stan models at runtime. rstan declares these
#                   as LinkingTo, but installing rstan as a BINARY skips them
#                   (LinkingTo is only needed to compile *against* a package, which
#                   a prebuilt binary doesn't), so Stan model compilation fails
#                   ("Boost not found" / "Eigen not found") without them. The brms
#                   smoke test below catches exactly this.
#   - remotes     : needed for the CatBoost URL install below
# CatBoost is not on CRAN — install its pinned linux-x86_64 release binary via
# remotes::install_url; the INSTALL_opts are what a clean binary install needs
# (per the catboost docs / the 2026-06 Posit tidymodels+catboost blog). The image
# is amd64-only (build.yml sets no platforms), so the x86_64 binary suffices. The
# end-to-end fit smoke test near the bottom proves the engine actually works —
# important, since we install it with --no-test-load.
RUN R -q -e 'options(repos = c(P3M = "https://packagemanager.posit.co/cran/__linux__/noble/latest")); pak::pkg_install(c("tidymodels", "bonsai", "remotes", "xgboost", "lightgbm", "randomForest", "ranger", "glmnet", "brms", "BH", "RcppEigen", "RcppParallel"))' \
 && R -q -e 'remotes::install_url("https://github.com/catboost/catboost/releases/download/v1.2.10/catboost-R-linux-x86_64-1.2.10.tgz", INSTALL_opts = c("--no-multiarch", "--no-test-load", "--no-staged-install"))'

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
RUN chmod -R g+w /usr/local/lib/R/site-library

# R smoke test: every baked-in package must actually load. Catches
# binary-ABI mismatches at build time instead of at Codespace-launch time.
# --vanilla skips Rprofile so this isolates the package-load path itself.
RUN R --vanilla -e 'for (p in c("pak", "httpgd")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Modeling smoke test 1: tidymodels, bonsai, every engine, and brms must load.
RUN R --vanilla -e 'for (p in c("tidymodels", "bonsai", "xgboost", "lightgbm", "randomForest", "ranger", "glmnet", "brms", "catboost")) if (!requireNamespace(p, quietly = TRUE)) stop("modeling smoke test failed to load: ", p)'

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
RUN claude --version && codex --version && agy --version && aider --version

# Locale (en_US.UTF-8) and timezone (Etc/UTC) are inherited from the rocker base.
