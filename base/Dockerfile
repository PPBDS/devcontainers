# syntax=docker/dockerfile:1.7

# Pinned by digest. The :4.4 tag floats as Rocker patches the image; the
# digest freezes us at a known build. To bump: pull :4.4 fresh, copy the
# new digest in, commit deliberately. Do not switch to :4.4 unpinned.
FROM ghcr.io/rocker-org/devcontainer/tidyverse:4.4@sha256:1b9c452558c17d282a5c5f19efb50f268366a1eb9dac54e3a3108b1688db002f

ARG QUARTO_VERSION=1.9.37
ARG ARF_VERSION=0.3.1
ARG NODE_MAJOR=22

# System libraries needed by both downstream images.
#  - Geospatial: sf, terra, etc.
#  - libnode-dev: satisfies the V8 R package (used by katex)
#  - text shaping libs: ragg / textshaping (modern ggplot2 graphics)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libudunits2-dev \
        libnode-dev \
        libfontconfig1-dev \
        libharfbuzz-dev \
        libfribidi-dev \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI. Official install method per the gh docs.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# AI coding-assistant CLIs. Three tools, three providers, three billing
# models. Students choose which to use and supply their own credentials
# via Codespaces user secrets (https://github.com/settings/codespaces):
#   - claude  (Claude Code, Anthropic) — needs ANTHROPIC_API_KEY
#   - gemini  (Gemini CLI, Google)     — free tier available, else GOOGLE_API_KEY
#   - aider   (multi-provider)         — supports DeepSeek/OpenRouter
#                                          for cost-sensitive usage
#
# Node hosts the two npm-distributed CLIs. We install from NodeSource
# rather than apt: Ubuntu Noble's nodejs is 18.x, but @google/gemini-cli
# bundles undici which needs the `File` global (Node 20+). NodeSource
# gives us a current LTS line (pinned via NODE_MAJOR above). pipx
# installs aider into an isolated venv with shims in /usr/local/bin (on
# every user's PATH), avoiding the PEP 668 lockout on Noble's system
# Python.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get install -y --no-install-recommends \
        nodejs \
        pipx \
    && rm -rf /var/lib/apt/lists/*

ENV PIPX_HOME=/opt/pipx \
    PIPX_BIN_DIR=/usr/local/bin

RUN npm install -g @anthropic-ai/claude-code @google/gemini-cli \
    && pipx install aider-chat

# Quarto. Use dpkg --print-architecture so the same Dockerfile works on
# amd64 and arm64 builders.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /tmp/quarto.deb \
        "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-${arch}.deb"; \
    dpkg -i /tmp/quarto.deb; \
    rm /tmp/quarto.deb; \
    quarto --version

# arf: Rust-based R console. Installed under the rstudio user so the binary
# lands at /home/rstudio/.cargo/bin/arf, matching what consumer
# devcontainer.json files reference as r.rterm.linux.
USER rstudio
RUN curl --proto '=https' --tlsv1.2 -fsSL \
        "https://github.com/eitsupi/arf/releases/download/v${ARF_VERSION}/arf-console-installer.sh" | sh
USER root

# Symlink arf to a stable system path so consumer devcontainer.json files
# don't have to hard-code "/home/rstudio/...". If the image's default user
# ever changes, only base/Dockerfile needs updating, not every consumer.
RUN ln -s /home/rstudio/.cargo/bin/arf /usr/local/bin/arf

# pak: fast parallel R package installer. Used by both downstream images,
# so install once at the base layer.
RUN R -q -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))'

# httpgd: graphics device used by both dev and student VS Code R extensions.
# No `upgrade = TRUE` here — httpgd is small, self-contained, and hasn't
# triggered a binary-ABI mismatch with rocker's pre-installed deps in
# practice. The smoke test at the bottom of this Dockerfile fails the
# build if that ever changes. (See student/Dockerfile for the case where
# upgrade = TRUE *is* load-bearing.)
RUN R -q -e 'pak::pkg_install("httpgd")'

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

# CLI smoke test: every shell tool must be on PATH and runnable.
RUN claude --version && gemini --version && aider --version

# Locale (en_US.UTF-8) and timezone (Etc/UTC) are inherited from the rocker base.
