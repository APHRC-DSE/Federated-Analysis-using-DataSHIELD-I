#!/usr/bin/env Rscript
# Step 4 — Create the dsOMOP CDM resource on each federated Opal site.
#
# For each of the three sites brought up in step 2 this script, via the Opal
# REST API (opalr):
#   1. ensures a resource-only Opal project exists (no storage DB needed),
#   2. (re)creates one OMOP CDM resource the dsOMOP resolver can pick up.
#
# No DataSHIELD privacy-control level is set here: dsOMOP v2 does its OWN
# statistical disclosure control (the nfilter.* thresholds plus a mandatory,
# non-disableable identifier strip) and never reads datashield.privacyControlLevel.
# Extraction works at any level once dsOMOP's assign methods are published on the
# Rock "omop" profile (handled by the image + easy-opal in step 2).
#
# How dsOMOP resources work:
#   - We register the resource through the dsOMOP resource provider with the
#     engine-specific factory ("postgresql" here). Opal then files it under the
#     "OMOP CDM Database" resource category and computes, server-side, the same
#     resolver-ready resource a hand-written URL would produce:
#         format == "omop.dbi.db"
#         url    == omop+dbi:postgresql://<host>:<port>/<database>?cdm_schema=...
#     The resolver in the Rock "omop" profile matches on that format.
#   - Connection details are passed as structured parameters (host, port,
#     database, cdm_schema). We give only the CDM schema: the vocabulary schema
#     defaults to it, and an omitted CDM schema would fall back to the engine
#     default (PostgreSQL: "public").
#   - DB credentials are NOT parameters; they are the resource identity/secret.
#   - host/port point at the PostgreSQL container over the site's Docker network
#     (alias "omopdb", internal port 5432 — from step 3), so the same resource
#     definition is valid on every site regardless of host port mapping.
#   - Binding to the dsOMOP provider also tells Opal which package backs the
#     resource, so no explicit package hint is needed (the federated analysis
#     loads dsOMOP through ds.omop.connect() in any case).
#
# Ports / credentials are HARDCODED below — the same fixed values steps 2, 3, 5
# and the book use. If you changed a port in step 2, change it here too.
#
# Usage (after steps 2 and 3):
#   bash 4_resources/setup_resources.sh
#   # or directly:  Rscript 4_resources/create_resources.R

suppressWarnings(suppressMessages({
  ok <- requireNamespace("opalr", quietly = TRUE)
}))
if (!ok) {
  message("==> installing opalr (CRAN) ...")
  install.packages("opalr", repos = "https://cloud.r-project.org")
}
library(opalr)

# --- fixed configuration (hardcoded; see steps 2-3) ------------------------
# The same localhost ports / public-demo credentials the earlier steps used.
# If you changed a port in step 2, change the matching one here too.
sites <- list(
  aphrc   = "http://localhost:48080",
  dgh     = "http://localhost:48081",
  iressef = "http://localhost:48082"
)
opal_user <- "administrator"
opal_pass <- "password"

# PostgreSQL connection details (identical on every site; from step 3). host/
# port are the Docker-internal alias the Rock 'omop' profile resolves, NOT a
# published host port, so this one resource definition is valid on all sites.
pg_host   <- "omopdb"        # docker network alias (step 3)
pg_port   <- 5432            # in-container PostgreSQL port
pg_db     <- "omop"
pg_schema <- "cdm"
pg_user   <- "postgres"      # intentional, public demo
pg_pass   <- "postgres"

project   <- "omop_demo"
resource  <- "gibleed"

cat(sprintf("Resource on each site: project='%s' name='%s' format='omop.dbi.db'\n",
            project, resource))
cat(sprintf("  -> %s://%s:%s/%s  schema=%s  (user '%s')\n\n",
            "postgresql", pg_host, pg_port, pg_db, pg_schema, pg_user))

# --- per-site provisioning --------------------------------------------------
for (site in names(sites)) {
  url <- sites[[site]]
  cat(sprintf("==> [%s] %s\n", site, url))

  o <- opal.login(username = opal_user, password = opal_pass, url = url)

  if (!opal.project_exists(o, project)) {
    cat(sprintf("    create project '%s' (resource-only)\n", project))
    opal.project_create(o, project, title = "dsOMOP federated demo")
  }

  # Recreate so re-runs always reflect the current config (create skips if it
  # already exists, so delete first).
  opal.resource_delete(o, project, resource, silent = TRUE)
  opal.resource_extension_create(
    o, project, name = resource,
    provider    = "dsOMOP",
    factory     = "postgresql",
    parameters  = list(host = pg_host, port = as.integer(pg_port),
                       database = pg_db, cdm_schema = pg_schema),
    credentials = list(username = pg_user, password = pg_pass),
    description = "OMOP CDM (GiBleed shard) for dsOMOP"
  )

  if (opal.resource_exists(o, project, resource)) {
    cat(sprintf("    resource '%s.%s' created OK\n\n", project, resource))
  } else {
    stop("resource creation failed on site ", site, call. = FALSE)
  }
  opal.logout(o)
}

cat(sprintf("==> Done. Resource '%s.%s' exists on %d site(s).\n",
            project, resource, length(sites)))
cat("Next: run the federated DataSHIELD analysis (step 5).\n")
