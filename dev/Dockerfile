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

# Package-development R packages. devtools/usethis/testthat/roxygen2 are
# already in the rocker tidyverse layer, but install explicitly so a future
# change to the base does not silently drop them. pak comes from base.
RUN R -q -e 'pak::pkg_install(c( \
        "devtools", \
        "pkgdown", \
        "roxygen2", \
        "testthat", \
        "usethis" \
    ))'
