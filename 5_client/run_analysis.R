#!/usr/bin/env Rscript
# Step 5 — Federated analysis across the three sites with dsOMOP + DataSHIELD.
#
# Logs the DataSHIELD client into all three sites (Rock profile "omop"),
# attaches the OMOP CDM resource created in step 4, and then:
#   A. explores the schema (tables / columns),
#   B. counts rows & persons per site and pooled  — the GiBleed cohort is
#      sharded by person across the sites, so the pooled person count is the
#      whole dataset (2694) while no site holds more than its shard,
#   C. computes the most prevalent conditions (pooled),
#   D. summarises a numeric measurement (per site + pooled),
#   E. extracts a person-level table server-side — renaming gender_concept_id
#      to a readable `sex` while the coordination layer still harmonises it into
#      a federation-aligned factor (identical level coding on every site), and
#   F. models that harmonised factor directly with dsBaseClient — a pooled-IPD
#      GLM and a meta-analytic GLM (SLMA) of birth year by sex.
#
# Nothing patient-level ever leaves a site: dsOMOP returns only disclosure-checked
# aggregates, and the table extracted in (E) is analysed in place by dsBase.
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

# --- fixed connection details (hardcoded; see steps 2-4) --------------------
# The same localhost ports / public-demo credentials the earlier steps set up.
# If you changed a port in step 2, change the matching one here too.
sites <- list(
  aphrc   = "http://localhost:48080",
  dgh     = "http://localhost:48081",
  iressef = "http://localhost:48082"
)
opal_user    <- "administrator"
opal_pass    <- "password"
opal_profile <- "omop"                      # Rock profile added in step 2
resource     <- "omop_demo.gibleed"         # project.resource created in step 4

# --- log in to every site (profile "omop") ---------------------------------
banner <- function(t) cat("\n", strrep("=", 70), "\n== ", t, "\n", strrep("=", 70), "\n", sep = "")
banner(sprintf("Logging in to %d site(s): %s", length(sites),
               paste(names(sites), collapse = ", ")))

builder <- DSI::newDSLoginBuilder()
for (site in names(sites)) {
  builder$append(server = site, url = sites[[site]],
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

# --- E. extract a person-level table (readable name + harmonised factor) -----
# We rename gender_concept_id -> `sex` in the recipe. Renaming a concept column
# does NOT opt it out of harmonisation: dsOMOP tags it by its landed name, so
# the coordination layer still recodes it into a factor coded identically on
# every site (8507 = MALE, 8532 = FEMALE). factor_concepts is on by default; we
# set it explicitly here for the narrative.
banner("E. Extract person-level table (rename-safe harmonised factor)")
analysis_ok <- tryCatch({
  plan <- ds.omop.plan()
  plan <- ds.omop.plan.person_level(
    plan, tables = list(person = c(sex = "gender_concept_id", "year_of_birth")),
    name = "demographics")
  plan <- ds.omop.plan.options(plan, factor_concepts = TRUE)
  ds.omop.plan.preview(plan, symbol = "omop", conns = conns)
  ds.omop.plan.execute(plan, out = c(demographics = "D"),
                       symbol = "omop", conns = conns)
  TRUE
}, error = function(e) { cat("Extraction failed: ", conditionMessage(e),
                             "\n(dsOMOP's assign methods must be published on the Rock 'omop' profile — see step 2.)\n",
                             sep = ""); FALSE })

if (isTRUE(analysis_ok)) {
  cat("\nExtracted server-side data frame 'D' — the column is `sex` (the\n",
      "_concept_id suffix renamed away) yet still harmonised:\n", sep = "")
  print(tryCatch(ds.dim("D"),      error = function(e) conditionMessage(e)))
  print(tryCatch(ds.colnames("D"), error = function(e) conditionMessage(e)))
  # Proof the rename did not break harmonisation: `sex` is a factor with the
  # SAME levels on every site — the precondition for pooling it in one model.
  cls <- tryCatch(ds.class("D$sex"),  error = function(e) NULL)
  lvl <- tryCatch(ds.levels("D$sex"), error = function(e) NULL)
  if (!is.null(cls))
    cat("\nds.class('D$sex') per site: ",
        paste(sprintf("%s=%s", names(cls),
                      vapply(cls, function(x) paste(unlist(x), collapse = "/"), "")),
              collapse = "  "), "\n", sep = "")
  if (!is.null(lvl)) {
    lchr <- lapply(lvl, function(x) as.character(if (!is.null(x$Levels)) x$Levels else unlist(x)))
    cat("ds.levels('D$sex') identical across sites: ", length(unique(lchr)) == 1L,
        "  ->  ", paste(lchr[[1]], collapse = ", "), "\n", sep = "")
  }
  cat("\nPooled mean year_of_birth:\n")
  print(tryCatch(ds.mean("D$year_of_birth", type = "combine"),
                 error = function(e) conditionMessage(e)))
  cat("\nSex distribution (harmonised factor, pooled + per site):\n")
  print(tryCatch(ds.table("D$sex"), error = function(e) conditionMessage(e)))
}

# --- F. model the harmonised factor directly (no manual recoding) -----------
# Because the coordination layer guarantees identical factor coding across the
# federation, `sex` is model-ready as-is — dsBaseClient builds the contrast for
# us, so the old ds.recodeValues 0/1 trick is no longer needed. The reference
# level is 8507 (MALE, the lowest id), so in `year_of_birth ~ sex` the intercept
# is the male mean birth year and the `sex8532` term is the female - male
# difference. We fit it two ways and confirm they agree:
#   (a) pooled IPD    ds.glm     — one model over the combined sufficient stats,
#   (b) meta-analytic ds.glmSLMA — fit per site, then meta-combine the estimates.
# No patient row ever leaves a server in either case.
if (isTRUE(analysis_ok)) {
  banner("F. Federated GLM on the harmonised factor (pooled IPD + meta-analysis)")

  cat("\n(a) Pooled IPD  —  ds.glm  year_of_birth ~ sex  (Gaussian):\n")
  fit <- tryCatch(ds.glm(formula = "D$year_of_birth ~ D$sex",
                         family = "gaussian", datasources = conns),
                  error = function(e) conditionMessage(e))
  print(if (is.list(fit)) fit$coefficients else fit)

  cat("\n(b) Meta-analytic  —  ds.glmSLMA  year_of_birth ~ sex  (Gaussian):\n")
  fit_slma <- tryCatch(ds.glmSLMA(formula = "D$year_of_birth ~ D$sex",
                                  family = "gaussian", datasources = conns),
                       error = function(e) conditionMessage(e))
  if (is.list(fit_slma)) {
    est <- fit_slma$SLMA.pooled.ests.matrix
    if (!is.null(est)) print(est) else print(fit_slma)
  } else print(fit_slma)
}

# --- tidy up ----------------------------------------------------------------
banner("Done — logging out")
try(ds.omop.disconnect(symbol = "omop", conns = conns), silent = TRUE)
DSI::datashield.logout(conns)
cat("Federated analysis complete.\n")
