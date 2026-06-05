# Rock R server for federated DataSHIELD analysis with dsOMOP v2.
#
# The upstream base (datashield/rock-base) already bundles the Rock server and
# dsBase. This image adds the OMOP CDM layer: resourcer + dsOMOP and its
# PostgreSQL driver (RPostgres). dsOMOP's Imports + its configure script pull
# DBI, R6, resourcer, jsonlite and arrow automatically.
#
# All upstream Rock bases are published for linux/amd64 ONLY, so build with:
#   docker buildx build --platform linux/amd64 ...
# It then runs natively on linux/amd64 servers and emulated on Apple Silicon.

ARG ROCK_BASE=datashield/rock-base:6.3.5-R4.5.3
FROM ${ROCK_BASE}

# Git ref (tag or commit SHA) in isglobal-brge/dsOMOP to install.
# Pinned to the v2.0.0 release. Equivalent commit:
#   a4dfe1a2c986af506d956aa19fed7ee32fb519b1
# Pass --build-arg DSOMOP_REF=<sha> to pin an exact commit instead of the tag.
ARG DSOMOP_REF=2.0.0

ENV ROCK_LIB=/var/lib/rock/R/library

USER root

# System library required to compile the PostgreSQL R driver.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Install resourcer + dsOMOP into the Rock package library.
# Use Posit Package Manager binaries (per OS codename) to avoid compiling arrow.
RUN CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")" \
 && Rscript -e "options(Ncpus = parallel::detectCores(), \
        repos = c(PPM = paste0('https://packagemanager.posit.co/cran/__linux__/', '$CODENAME', '/latest'), \
                  CRAN = 'https://cloud.r-project.org')); \
      if (!requireNamespace('remotes', quietly = TRUE)) install.packages('remotes'); \
      remotes::install_github('isglobal-brge/dsOMOP', ref = '$DSOMOP_REF', upgrade = 'never', lib = Sys.getenv('ROCK_LIB'))" \
 && chown -R rock:rock "$ROCK_LIB"

# Sanity check: dsOMOP and its key dependencies load from the Rock library.
RUN Rscript -e ".libPaths(c(Sys.getenv('ROCK_LIB'), .libPaths())); \
      library(dsOMOP); library(resourcer); library(RPostgres); \
      cat('dsOMOP', as.character(packageVersion('dsOMOP')), 'OK\n')"

# Leave the image running as root (like the rock-base parent): the Rock
# entrypoint starts as root and drops privileges to the 'rock' user itself.
# Pinning USER rock here makes that switch fail ("operation not permitted")
# and the server crash-loops — notably under QEMU emulation on Apple Silicon.
