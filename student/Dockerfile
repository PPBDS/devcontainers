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
RUN R -q -e 'pak::pkg_install(c( \
        "PPBDS/tutorial.helpers", \
        "PPBDS/vscode.tutorials" \
    ), upgrade = TRUE)'

# Restore group-write on site-library (the install above ran as root).
# See base/Dockerfile for rationale.
RUN chmod -R g+w /usr/local/lib/R/site-library

# Smoke test: every baked-in package and the learnr/knitr/rmarkdown chain
# must all load. The original learnr/xfun ABI mismatch failure would have
# been caught here at build time.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "learnr", "knitr", "rmarkdown")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'
