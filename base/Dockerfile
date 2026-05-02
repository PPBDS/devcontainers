# syntax=docker/dockerfile:1.7

# Pinned by digest. The :4.4 tag floats as Rocker patches the image; the
# digest freezes us at a known build. To bump: pull :4.4 fresh, copy the
# new digest in, commit deliberately. Do not switch to :4.4 unpinned.
FROM ghcr.io/rocker-org/devcontainer/tidyverse:4.4@sha256:1b9c452558c17d282a5c5f19efb50f268366a1eb9dac54e3a3108b1688db002f

ARG QUARTO_VERSION=1.9.37
ARG ARF_VERSION=0.3.1

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

# pak: fast parallel R package installer. Used by both downstream images,
# so install once at the base layer.
RUN R -q -e 'install.packages("pak", repos = sprintf("https://r-lib.github.io/p/pak/stable/%s/%s/%s", .Platform$pkgType, R.Version()$os, R.Version()$arch))'

# httpgd: graphics device used by both dev and student VS Code R extensions.
# upgrade = TRUE forces pak to pull the latest version of every dependency
# (not just "whatever already satisfies the minimum"). Without this, a
# binary package built against a newer dependency than what rocker shipped
# can fail to load with "object 'X' is not exported by 'namespace:Y'".
RUN R -q -e 'pak::pkg_install("httpgd", upgrade = TRUE)'

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

# Locale (en_US.UTF-8) and timezone (Etc/UTC) are inherited from the rocker base.
