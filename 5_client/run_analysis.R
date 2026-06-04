#!/usr/bin/env Rscript
# Step 5 — Federated analysis across the three sites with dsOMOP + DataSHIELD.
#
# Reads ../sites.env, logs the DataSHIELD client into all sites (Rock profile
# "omop"), attaches the OMOP CDM resource created in step 4, and then:
#   A. explores the schema (tables / columns),
#   B. counts rows & persons per site and pooled  — the GiBleed cohort is
#      sharded by person across the sites, so the pooled person count is the
#      whole dataset (2694) while no site holds more than its shard,
#   C. computes the most prevalent conditions (pooled),
#   D. summarises a numeric measurement (per site + pooled),
#   E. extracts a person-level table server-side and runs a standard
#      dsBaseClient analysis on it — showing dsOMOP output flows into the normal
#      DataSHIELD toolchain.
#
# Nothing patient-level ever leaves a site: dsOMOP returns only disclosure-checked
# aggregates, and the extracted table in (E) is analysed in place by dsBase.
#
# Usage (after steps 2-4):  bash 5_client/setup_client.sh
#   or directly:            Rscript 5_client/run_analysis.R

needed <- c("DSI", "DSOpal", "dsBaseClient", "dsOMOPClient")
missing <- needed[!vapply(needed, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) {
  stop("Missing client package(s): ", paste(missing, collapse = ", "),
       "\n  Install them first:  Rscript 5_client/install_client.R", call. = FALSE)
}
suppressPackageStartupMessages({
  library(DSI); library(DSOpal); library(dsBaseClient); library(dsOMOPClient)
})

# --- locate + parse sites.env ----------------------------------------------
script_path <- (function() {
  a <- commandArgs(FALSE); f <- sub("^--file=", "", a[grepl("^--file=", a)])
  if (length(f)) normalizePath(f) else NA_character_
})()
repo_root <- if (!is.na(script_path)) dirname(dirname(script_path)) else getwd()
sites_env <- Sys.getenv("SITES_ENV", unset = file.path(repo_root, "sites.env"))
if (!file.exists(sites_env))
  stop("sites.env not found at ", sites_env, " — run steps 2-4 first.", call. = FALSE)

read_env <- function(path) {
  lines <- trimws(readLines(path, warn = FALSE))
  lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
  m <- regmatches(lines, regexec("^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", lines))
  env <- list(); for (kv in m) if (length(kv) == 3L) env[[kv[2]]] <- kv[3]; env
}
cfg <- read_env(sites_env)
req <- function(k) { v <- cfg[[k]]
  if (is.null(v) || !nzchar(v)) stop("Missing '", k, "' in ", sites_env,
    " — re-run the earlier steps.", call. = FALSE); v }

opal_user    <- req("OPAL_USER")
opal_pass    <- req("OPAL_PASSWORD")
opal_profile <- if (!is.null(cfg$OPAL_PROFILE) && nzchar(cfg$OPAL_PROFILE)) cfg$OPAL_PROFILE else "omop"
resource     <- req("OPAL_RESOURCE_PATH")          # e.g. "omop_demo.gibleed" (from step 4)

url_keys <- grep("_OPAL_URL$", names(cfg), value = TRUE)
if (!length(url_keys)) stop("No <SITE>_OPAL_URL in ", sites_env, call. = FALSE)
sites <- sub("_OPAL_URL$", "", url_keys)

# --- log in to every site (profile "omop") ---------------------------------
banner <- function(t) cat("\n", strrep("=", 70), "\n== ", t, "\n", strrep("=", 70), "\n", sep = "")
banner(sprintf("Logging in to %d site(s): %s", length(sites),
               paste(tolower(sites), collapse = ", ")))

builder <- DSI::newDSLoginBuilder()
for (S in sites) {
  builder$append(server = tolower(S), url = cfg[[paste0(S, "_OPAL_URL")]],
                 user = opal_user, password = opal_pass,
                 resource = resource, driver = "OpalDriver", profile = opal_profile)
}
conns <- DSI::datashield.login(logins = builder$build())

# Attach the OMOP resource on all servers (assigns + initialises dsOMOP).
ds.omop.connect(resource = resource, symbol = "omop", conns = conns)

# Helper: print the $pooled and $per_site parts of a dsOMOP result.
show <- function(res, what) {
  cat("\n-- ", what, " --\n", sep = "")
  if (!is.null(res$pooled))   { cat("[pooled]\n");   print(res$pooled) }
  if (!is.null(res$per_site)) { cat("[per site]\n"); print(res$per_site) }
  if (is.null(res$pooled) && is.null(res$per_site)) print(res)
  invisible(res)
}
try_show <- function(expr, what)
  tryCatch(show(expr, what),
           error = function(e) cat("\n-- ", what, " -- skipped: ",
                                   conditionMessage(e), "\n", sep = ""))

# --- A. schema exploration --------------------------------------------------
banner("A. Schema exploration")
tabs <- tryCatch(ds.omop.tables(symbol = "omop", conns = conns), error = function(e) NULL)
if (!is.null(tabs)) {
  s1 <- tabs[[1]]
  cat(sprintf("Tables visible on '%s': %s\n", names(tabs)[1],
              if (is.data.frame(s1)) nrow(s1) else length(unlist(s1))))
  print(utils::head(s1, 10))
}
cols <- tryCatch(ds.omop.columns("person", symbol = "omop", conns = conns), error = function(e) NULL)
if (!is.null(cols)) { cat("\nColumns of `person` (first site):\n"); print(cols[[1]]) }

# --- B. federated row / person counts --------------------------------------
banner("B. Federated counts (rows & persons) per site and pooled")
for (tb in c("person", "condition_occurrence", "drug_exposure", "measurement"))
  try_show(ds.omop.table.stats(tb, symbol = "omop", conns = conns),
           sprintf("table.stats(%s)", tb))

# --- C. most prevalent conditions (pooled) ----------------------------------
banner("C. Most prevalent conditions (pooled across sites)")
try_show(ds.omop.concept.prevalence("condition_occurrence", metric = "persons",
                                     top_n = 15, scope = "pooled",
                                     symbol = "omop", conns = conns),
         "concept.prevalence(condition_occurrence)")

# --- D. numeric value quantiles ---------------------------------------------
# GiBleed records all measurements categorically (value_as_concept_id); its
# measurement.value_as_number is entirely NULL, so we profile a populated
# numeric field instead: drug_exposure.days_supply.
banner("D. Drug-exposure days-supply quantiles (per site)")
try_show(ds.omop.value.quantiles("drug_exposure", "days_supply",
                                  probs = c(0.25, 0.5, 0.75),
                                  symbol = "omop", conns = conns),
         "value.quantiles(drug_exposure$days_supply)")

# --- E. extract a person-level table, then standard DataSHIELD --------------
banner("E. Extract person-level table -> standard dsBaseClient analysis")
analysis_ok <- tryCatch({
  plan <- ds.omop.plan()
  plan <- ds.omop.plan.person_level(
    plan, tables = list(person = c("gender_concept_id", "year_of_birth")),
    name = "demographics")
  ds.omop.plan.preview(plan, symbol = "omop", conns = conns)
  ds.omop.plan.execute(plan, out = c(demographics = "D"),
                       symbol = "omop", conns = conns)
  TRUE
}, error = function(e) { cat("Extraction failed: ", conditionMessage(e),
                             "\n(dsOMOP's assign methods must be published on the Rock 'omop' profile — see step 2.)\n",
                             sep = ""); FALSE })

if (isTRUE(analysis_ok)) {
  cat("\nExtracted server-side data frame 'D':\n")
  print(tryCatch(ds.dim("D"),      error = function(e) conditionMessage(e)))
  print(tryCatch(ds.colnames("D"), error = function(e) conditionMessage(e)))
  # ds.summary confirms the dsOMOP extract is now an ordinary R data.frame on
  # each server — the point where the OMOP layer hands off to standard DataSHIELD.
  cat("\nds.summary('D') — the extract is now a normal server-side R data.frame:\n")
  print(tryCatch(ds.summary("D")[[1]], error = function(e) conditionMessage(e)))
  cat("\nPooled mean year_of_birth:\n")
  print(tryCatch(ds.mean("D$year_of_birth", type = "combine"),
                 error = function(e) conditionMessage(e)))
  cat("\nGender distribution (concept id):\n")
  print(tryCatch(ds.table("D$gender_concept_id"),
                 error = function(e) conditionMessage(e)))
}

# --- F. model the extracted table with a standard dsBaseClient GLM ----------
# Because 'D' is just a server-side data.frame, the whole dsBaseClient modelling
# toolchain applies directly to a dsOMOP extract. As an illustration we ask
# whether birth year differs by sex: recode gender_concept_id (8507 male /
# 8532 female) to a 0/1 indicator, bind a model frame, and fit a federated
# linear model pooled across all three sites. No patient row ever leaves a
# server — only the model's sufficient statistics are combined. (The fitted
# intercept is the female mean birth year and the slope the male-female
# difference, so the result is directly interpretable.)
if (isTRUE(analysis_ok)) {
  banner("F. Federated GLM on the extracted table (dsBaseClient::ds.glm)")
  model_ok <- tryCatch({
    ds.recodeValues(var.name = "D$gender_concept_id",
                    values2replace.vector = c(8507, 8532),
                    new.values.vector = c(1, 0),
                    newobj = "male", datasources = conns)
    ds.dataFrame(x = c("D", "male"), newobj = "DF", datasources = conns)
    TRUE
  }, error = function(e) {
    cat("Model-frame prep failed: ", conditionMessage(e), "\n", sep = ""); FALSE
  })
  if (isTRUE(model_ok)) {
    cat("\nLinear model  year_of_birth ~ male  (Gaussian, pooled across sites):\n")
    fit <- tryCatch(ds.glm(formula = "DF$year_of_birth ~ DF$male",
                           family = "gaussian", datasources = conns),
                    error = function(e) conditionMessage(e))
    print(if (is.list(fit)) fit$coefficients else fit)
  }
}

# --- tidy up ----------------------------------------------------------------
banner("Done — logging out")
try(ds.omop.disconnect(symbol = "omop", conns = conns), silent = TRUE)
DSI::datashield.logout(conns)
cat("Federated analysis complete.\n")
