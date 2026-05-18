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
