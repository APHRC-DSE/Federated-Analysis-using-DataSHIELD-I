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
# How dsOMOP v2 resources work (this is NOT the stale README/v1 format):
#   - The resolver in the Rock "omop" profile matches resources whose
#     format == "omop.dbi.db".
#   - All connection details travel in the resource URL, encoded so the Opal R
#     URL parser cannot choke on them:
#         omop+dbi:///B64:<base64url(JSON)>
#     where JSON = {dbms, host, port, database, cdm_schema, vocabulary_schema}.
#   - DB credentials are NOT in the URL; they are the resource's identity/secret.
#   - host/port point at the PostgreSQL container over the site's Docker network
#     (alias "omopdb", internal port 5432 — from step 3), so the same resource
#     definition is valid on every site regardless of host port mapping.
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

# --- build the dsOMOP resource URL (matches dsOMOP 2.0.0 R/resource.R) ------
make_omop_url <- function(dbms, host, port, database, cdm_schema,
                          vocabulary_schema = NULL) {
  config <- list(dbms = dbms, host = host, port = as.integer(port),
                 database = database, cdm_schema = cdm_schema)
  if (!is.null(vocabulary_schema)) config$vocabulary_schema <- vocabulary_schema
  json <- as.character(jsonlite::toJSON(config, auto_unbox = TRUE))
  b64 <- gsub("[\r\n]", "", jsonlite::base64_enc(charToRaw(json)))
  b64 <- gsub("+", "-", b64, fixed = TRUE)   # base64url: + -> -
  b64 <- gsub("/", "_", b64, fixed = TRUE)   #            / -> _
  b64 <- gsub("=+$", "", b64)                # strip padding
  paste0("omop+dbi:///B64:", b64)
}

# Single schema in this demo: the vocabulary tables (concept, ...) live in the
# same "cdm" schema, so vocabulary_schema == cdm_schema.
omop_url <- make_omop_url(
  dbms = "postgresql", host = pg_host, port = pg_port,
  database = pg_db, cdm_schema = pg_schema, vocabulary_schema = pg_schema
)

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
  opal.resource_create(o, project, name = resource, url = omop_url,
                       description = "OMOP CDM (GiBleed shard) for dsOMOP",
                       format = "omop.dbi.db",
                       identity = pg_user, secret = pg_pass)

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
