# syntax=docker/dockerfile:1.7

ARG BASE_TAG=latest
FROM ghcr.io/ppbds/devcontainers/base:${BASE_TAG}

# tutorial.helpers from the PPBDS r-universe. *Prepend* PPBDS to the
# existing repo list rather than replacing it — the rocker base ships
# with Posit Public Package Manager (P3M) configured as the CRAN repo,
# which serves Linux binaries. Replacing it forces source builds for
# transitive deps (e.g., learnr), which can hit cross-version breakage.
# Add primer, ai.tutorials, etc. to the install vector when needed.
RUN R -q -e 'options(repos = c( \
        PPBDS = "https://ppbds.r-universe.dev", \
        getOption("repos") \
    )); \
    pak::pkg_install("tutorial.helpers", upgrade = TRUE)'

# Restore group-write on site-library (the install above ran as root).
# See base/Dockerfile for rationale.
RUN chmod -R g+w /usr/local/lib/R/site-library
