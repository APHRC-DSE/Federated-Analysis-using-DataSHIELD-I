#!/usr/bin/env Rscript
# Step 4 — Create the dsOMOP CDM resource on each federated Opal site.
#
# For every site brought up in step 2 (read from ../sites.env) this script, via
# the Opal REST API (opalr):
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
# Usage (after steps 2 and 3):
#   bash 4_resources/setup_resources.sh
#   # or directly:  Rscript 4_resources/create_resources.R
#
# Overridable via environment:
#   OPAL_PROJECT (default "omop_demo"), OPAL_RESOURCE (default "gibleed"),
#   SITES_ENV (default ../sites.env).

suppressWarnings(suppressMessages({
  ok <- requireNamespace("opalr", quietly = TRUE)
}))
if (!ok) {
  message("==> installing opalr (CRAN) ...")
  install.packages("opalr", repos = "https://cloud.r-project.org")
}
library(opalr)

# --- locate + parse sites.env ----------------------------------------------
script_path <- (function() {
  a <- commandArgs(FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(f) else NA_character_
})()
repo_root <- if (!is.na(script_path)) dirname(dirname(script_path)) else getwd()
sites_env <- Sys.getenv("SITES_ENV", unset = file.path(repo_root, "sites.env"))

if (!file.exists(sites_env)) {
  stop("sites.env not found at ", sites_env,
       "\n  Run step 2 (sites) and step 3 (databases) first.", call. = FALSE)
}

read_env <- function(path) {
  lines <- trimws(readLines(path, warn = FALSE))
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  m <- regmatches(lines, regexec("^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", lines))
  env <- list()
  for (kv in m) if (length(kv) == 3L) env[[kv[2]]] <- kv[3]
  env
}
cfg <- read_env(sites_env)

req <- function(key) {
  v <- cfg[[key]]
  if (is.null(v) || !nzchar(v))
    stop("Missing '", key, "' in ", sites_env,
         " — re-run the earlier steps.", call. = FALSE)
  v
}

# Sites are every <SITE>_OPAL_URL present in sites.env (written by step 2).
url_keys <- grep("_OPAL_URL$", names(cfg), value = TRUE)
if (!length(url_keys))
  stop("No <SITE>_OPAL_URL entries in ", sites_env, " — run step 2 first.",
       call. = FALSE)
sites <- sub("_OPAL_URL$", "", url_keys)             # e.g. APHRC, DGH, IRESSEF

opal_user    <- req("OPAL_USER")
opal_pass    <- req("OPAL_PASSWORD")

# PostgreSQL connection details (identical across sites; from step 3).
pg_host   <- req("PG_HOST_ALIAS")      # Docker network alias, not a host port
pg_port   <- req("PG_INTERNAL_PORT")   # in-container port (5432)
pg_db     <- req("PG_DATABASE")
pg_schema <- req("PG_SCHEMA")
pg_user   <- req("PG_USER")
pg_pass   <- req("PG_PASSWORD")

project       <- Sys.getenv("OPAL_PROJECT", unset = "omop_demo")
resource      <- Sys.getenv("OPAL_RESOURCE", unset = "gibleed")

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
for (SITE in sites) {
  url <- cfg[[paste0(SITE, "_OPAL_URL")]]
  site <- tolower(SITE)
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

# --- record choices for step 5 ---------------------------------------------
# Refresh a step-4 block in sites.env (drop any previous one, then append).
mark <- "# === step 4 (resources) — appended by 4_resources/create_resources.R ==="
all_lines <- readLines(sites_env, warn = FALSE)
cut <- which(all_lines == mark)
if (length(cut)) all_lines <- all_lines[seq_len(cut[1] - 1L)]
# Drop a trailing blank line so we don't accumulate blanks across re-runs.
while (length(all_lines) && !nzchar(trimws(all_lines[length(all_lines)])))
  all_lines <- all_lines[-length(all_lines)]

block <- c(
  "",
  mark,
  paste0("OPAL_PROJECT=", project),
  paste0("OPAL_RESOURCE=", resource),
  paste0("OPAL_RESOURCE_PATH=", project, ".", resource)
)
writeLines(c(all_lines, block), sites_env)

cat(sprintf("==> Done. Resource '%s.%s' exists on %d site(s).\n",
            project, resource, length(sites)))
cat(sprintf("    Recorded OPAL_RESOURCE_PATH=%s.%s in %s\n",
            project, resource, sites_env))
cat("Next: run the federated DataSHIELD analysis (step 5).\n")
