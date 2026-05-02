# syntax=docker/dockerfile:1.7

ARG BASE_TAG=latest
FROM ghcr.io/ppbds/devcontainers/base:${BASE_TAG}

# tutorial.helpers from the PPBDS r-universe (binary build of GitHub HEAD —
# fast install, no compile toolchain needed at runtime). When more course
# packages need to ship pre-installed (primer, ai.tutorials, etc.), add
# them to the vector below.
RUN R -q -e 'options(repos = c( \
        PPBDS = "https://ppbds.r-universe.dev", \
        CRAN  = "https://cloud.r-project.org" \
    )); \
    pak::pkg_install("tutorial.helpers")'
