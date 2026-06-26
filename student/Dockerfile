# syntax=docker/dockerfile:1.7

ARG BASE_TAG=latest
FROM ghcr.io/ppbds/devcontainers/base:${BASE_TAG}

# Course R packages, both installed from GitHub source via pak so a fresh
# image always tracks the latest commit on each package's default branch.
# This matches PPBDS practice — codespace-starter's old setup.sh did the
# same, with the rationale that the rest of the PPBDS ecosystem expects
# the development version, not whatever an r-universe build cycle (or
# CRAN) most recently blessed.
#
# Add primer, ai.tutorials, etc. as further "PPBDS/<name>" entries here
# when the syllabus needs them baked in.
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
        "PPBDS/vscode.tutorials" \
    ), upgrade = TRUE)'

# Smoke test 1: every baked-in package and the learnr/knitr/rmarkdown
# chain must all load. The original learnr/xfun ABI mismatch failure
# would have been caught here at build time.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "learnr", "knitr", "rmarkdown")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'

# Smoke test 2: rstudio can install a fresh package into site-library
# without permission errors. Catches the "root-built image leaves
# unwritable lock files" regression at build time instead of at
# first-student-pak-call time. praise is tiny (~5KB) and dependency-free.
RUN R --vanilla -e 'install.packages("praise", repos = "https://cloud.r-project.org"); if (!requireNamespace("praise", quietly = TRUE)) stop("rstudio cannot install into site-library — check site-library permissions in base image")' \
 && R --vanilla -e 'remove.packages("praise")'

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
#                   download, so it's the same interpreter R's reticulate uses.
#   chgrp staff + g+w → make the venv group-writable (rstudio is in staff), the
#                   same treatment base gives R's site-library, so a student's
#                   `pip install` actually has somewhere to write.
# /opt/venv goes first on PATH and is wired to RETICULATE_PYTHON — a deliberate
# single-Python choice rather than maintaining two interpreters. uv's own binary
# is copied from its official pinned image (no curl-pipe; pinned, unlike agy).
COPY --from=ghcr.io/astral-sh/uv:0.11.23 /uv /usr/local/bin/uv
COPY requirements.lock /tmp/requirements.lock
RUN uv venv --seed --python /usr/bin/python3 /opt/venv \
    && uv pip install --python /opt/venv/bin/python --no-cache -r /tmp/requirements.lock \
    && /opt/venv/bin/python -m ipykernel install --prefix /usr/local \
         --name python3 --display-name "Python (data science)" \
    && chgrp -R staff /opt/venv \
    && chmod -R g+w /opt/venv \
    && rm /tmp/requirements.lock
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

# ── R interactive-visualisation + Shinylive packages ─────────────────────────
# htmlwidgets for "fancy" interactive output that still publishes to STATIC
# hosting (GitHub Pages): plotly + leaflet (charts/maps), DT (interactive
# tables), crosstalk (client-side linking/filtering, no server). Plus shiny +
# shinylive, which compile a Shiny app to WebAssembly (webR) so it too runs on
# a static host. Installed via pak as rstudio — P3M serves Linux binaries, so
# this is fast (~16 s) and ~70 MB. (Python equivalents — plotly/altair/folium/
# itables/shiny/shinylive — are in requirements.txt.)
USER rstudio
RUN R -q -e 'pak::pkg_install(c("plotly", "leaflet", "DT", "crosstalk", "shiny", "shinylive"))' \
    && R --vanilla -e 'for (p in c("plotly","leaflet","DT","crosstalk","shiny","shinylive")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'
USER root
# ─────────────────────────────────────────────────────────────────────────────
