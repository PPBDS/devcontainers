# syntax=docker/dockerfile:1.7

ARG BASE_TAG=latest
FROM ghcr.io/ppbds/devcontainers/base:${BASE_TAG}

# Course R packages.
# - tutorial.helpers from the PPBDS r-universe (binary install).
# - vscode.tutorials from GitHub source — not yet on the r-universe.
#   Switch to the bare name "vscode.tutorials" (binary) once the package
#   is registered at https://ppbds.r-universe.dev.
# Prepend PPBDS to the existing repo list rather than replacing it — the
# rocker base ships with Posit Public Package Manager (P3M) configured as
# the CRAN repo, which serves Linux binaries. Replacing it would force
# source builds for transitive deps (e.g., learnr), which can hit
# cross-version breakage. Add primer, ai.tutorials, etc. when needed.
RUN R -q -e 'options(repos = c( \
        PPBDS = "https://ppbds.r-universe.dev", \
        getOption("repos") \
    )); \
    pak::pkg_install(c( \
        "tutorial.helpers", \
        "PPBDS/vscode.tutorials" \
    ), upgrade = TRUE)'

# Restore group-write on site-library (the install above ran as root).
# See base/Dockerfile for rationale.
RUN chmod -R g+w /usr/local/lib/R/site-library

# Smoke test: every baked-in package and the learnr/knitr/rmarkdown chain
# must all load. The original learnr/xfun ABI mismatch failure would have
# been caught here at build time.
RUN R --vanilla -e 'for (p in c("tutorial.helpers", "vscode.tutorials", "learnr", "knitr", "rmarkdown")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'
