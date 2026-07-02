# syntax=docker/dockerfile:1.7

ARG BASE_TAG=latest
FROM ghcr.io/ppbds/devcontainers/base:${BASE_TAG}

# Never let pak try to `sudo apt-get install` system requirements. The system
# libraries our packages need are baked into the base image; pak running as the
# non-root rstudio user can't sudo, and (e.g. for V8's libnode-dev) it even
# mis-detects baked libs as missing and tries anyway, which fails the build /
# postCreate / a student's runtime install. With this off pak still PRINTS any
# sysreqs but builds against the baked libs. (Add new system deps to
# base/Dockerfile, not via pak.) Applies to the build, postCreate, and runtime.
ENV PKG_SYSREQS=false

# Course R packages, all installed from GitHub source via pak so a fresh
# image always tracks the latest commit on each package's default branch.
# This matches PPBDS practice — codespace-starter's old setup.sh did the
# same, with the rationale that the rest of the PPBDS ecosystem expects
# the development version, not whatever an r-universe build cycle (or
# CRAN) most recently blessed.
#
# These four are also refreshed to the latest commit on every Codespace
# create via codespace-starter's postCreateCommand; baking them here pre-
# installs the whole dependency tree (so that refresh is a quick update, not
# a cold build) and leaves a working fallback if GitHub is unreachable. Note
# primer.tutorials lives in a SUBDIR of the primer repo, hence the
# "PPBDS/primer/primer.tutorials" path. Add further "PPBDS/<name>" entries
# (in BOTH places) when the syllabus needs them.
#
# upgrade = TRUE forces pak to pull the latest version of every
# transitive dep (learnr, knitr, rmarkdown, xfun, ...). Without this, a
# binary dep built against a newer version of xfun than what rocker
# shipped fails to load with "object 'attr' is not exported by
# 'namespace:xfun'".
#
# We run the install as the rstudio user, not root. This is the design
# fix for a class of permissions bugs: when pak runs as root inside the
# build, it drops lock files in site-library as -rw--w---- (group write
# but no read, due to root's restrictive umask), which then blocks every
# subsequent install by the non-root rstudio user with
# "filelock::lock(): Permission denied". Running the install as rstudio
# in the first place means the lock files get a normal umask and never
# poison the library for later installs.
#
# This relies on the base image already setting up site-library as
# drwxrwsr-x with group=staff and rstudio in the staff group (Rocker's
# default; see base/Dockerfile).
USER rstudio
RUN R -q -e 'pak::pkg_install(c( \
        "PPBDS/tutorial.helpers", \
        "PPBDS/vscode.tutorials", \
        "PPBDS/misc.tutorials", \
        "PPBDS/primer/primer.tutorials" \
    ), upgrade = TRUE)'

# Smoke test 1: every baked-in package and the learnr/knitr/rmarkdown
# chain must all load. The original learnr/xfun ABI mismatch failure
# would have been caught here at build time.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "misc.tutorials", "primer.tutorials", "learnr", "knitr", "rmarkdown")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Smoke test 2: rstudio can install a fresh package into site-library
# without permission errors. Catches the "root-built image leaves
# unwritable lock files" regression at build time instead of at
# first-student-pak-call time. praise is tiny (~5KB) and dependency-free.
RUN R --vanilla -e 'install.packages("praise", repos = "https://cloud.r-project.org"); if (!requireNamespace("praise", quietly = TRUE)) stop("rstudio cannot install into site-library — check site-library permissions in base image")' \
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
# sf (vector geodata; links against the GDAL/PROJ/GEOS/udunits system libs that
# base bakes for exactly this) and tidycensus (ACS/decennial data + geometry in
# one call; pulls in tigris for TIGER shapefiles). Students need a free Census
# API key for live tidycensus queries. P3M Linux binaries, so this is fast.
# The interactive path needs nothing more: leaflet (above) draws sf objects,
# and free CARTO basemap tiles substitute for Mapbox.
RUN R -q -e 'pak::pkg_install(c("sf", "tidycensus"))' \
    && R --vanilla -e 'for (p in c("sf","tidycensus","tigris")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)' \
    && R --vanilla -e 'library(sf); p <- st_sfc(st_polygon(list(rbind(c(0,0), c(1,0), c(1,1), c(0,1), c(0,0)))), crs = 4326); pts <- st_sample(p, 10); stopifnot(length(pts) == 10); cat("sf geometry ops OK\n")'

USER root

# ── Python data-science stack ────────────────────────────────────────────────
# Lets students do data science in Python too, not just R: numpy/pandas
# (wrangling), matplotlib/seaborn (plots), scikit-learn (ML), statsmodels
# (regression/inference — the lm() analog), and jupyter/ipykernel (notebooks;
# also what Quarto's Python engine and the VS Code Jupyter extension drive).
# We pin the full dependency tree in student/requirements.lock (generated from
# student/requirements.txt via `uv pip compile`); edit the .txt and recompile to
# bump versions.
#
# Installed with uv (Astral's fast resolver/installer) into a venv at /opt/venv:
#   --seed        → put pip/setuptools/wheel IN the venv, so students can plain
#                   `pip install` more packages (uv venvs omit pip by default).
#   --python /usr/bin/python3 → use the system CPython, NOT a uv-managed
#                   download, so it's a normal, predictable interpreter.
#   chgrp staff + g+w → make the venv group-writable (rstudio is in staff), the
#                   same treatment base gives R's site-library, so a student's
#                   `pip install` actually has somewhere to write.
# /opt/venv goes first on PATH, so `python`/`pip`/`jupyter` are the venv's.
# Quarto runs Python via the jupyter engine (ipykernel) — no reticulate needed.
# We still set RETICULATE_PYTHON so that IF someone installs R's reticulate
# (not baked in) it bridges to this same venv rather than a separate Python.
# uv's own binary is copied from its official pinned image (pinned, unlike agy).
COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /usr/local/bin/uv
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
# build`). Node is already present (base, for the AI CLIs); ~84 MB on disk.
#
# NOTE: interactive Observable charts INSIDE a Quarto document need NOTHING
# extra — Quarto's bundled `{ojs}` cells already render Observable Plot / OJS
# (build-test verified). Framework is only for standalone data-app projects.
# The `observable --version` call is the smoke test (fails the build if broken).
RUN npm install -g @observablehq/framework@1.13.4 && observable --version
# ─────────────────────────────────────────────────────────────────────────────

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
