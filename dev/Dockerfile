# syntax=docker/dockerfile:1.7

# BASE_TAG is set by the CI workflow to the SHA-pinned tag of the base image
# built in the same run, so dev and base never drift within a build.
# Defaults to :latest for ad-hoc local builds.
ARG BASE_TAG=latest
FROM ghcr.io/ppbds/devcontainers/base:${BASE_TAG}

# qpdf is required by `R CMD check --as-cran` for PDF manual checks.
# rocker/tidyverse already provides the rest of the build/check toolchain.
RUN apt-get update && apt-get install -y --no-install-recommends \
        qpdf \
    && rm -rf /var/lib/apt/lists/*

# Package-development R packages. pak comes from base. upgrade = TRUE
# pulls latest versions of all transitive deps to avoid binary-ABI
# mismatches — see base/Dockerfile for the failure mode.
RUN R -q -e 'pak::pkg_install(c( \
        "devtools", \
        "pkgdown", \
        "roxygen2", \
        "testthat", \
        "usethis" \
    ), upgrade = TRUE)'

# Restore group-write on site-library (the install above ran as root).
# See base/Dockerfile for rationale.
RUN chmod -R g+w /usr/local/lib/R/site-library

# Smoke test: every package baked in must actually load.
RUN R --vanilla -e 'for (p in c("devtools", "pkgdown", "roxygen2", "testthat", "usethis")) if (!requireNamespace(p, quietly = TRUE)) stop("smoke test failed to load: ", p)'
