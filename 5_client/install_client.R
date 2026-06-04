#!/usr/bin/env Rscript
# Step 5a — Install the DataSHIELD client stack used by run_analysis.R.
#
# Idempotent: anything already present is left alone. Pins dsOMOPClient to the
# 2.0.0 git tag (the version this package was written against); DSI/DSOpal come
# from CRAN and dsBaseClient from the DataSHIELD package repo.

cran <- "https://cloud.r-project.org"
dsr  <- "https://cran.datashield.org"

have <- function(pkg) requireNamespace(pkg, quietly = TRUE)

if (!have("DSI"))    install.packages("DSI",    repos = cran)
if (!have("DSOpal")) install.packages("DSOpal", repos = cran)   # Opal driver for DSI
if (!have("dsBaseClient"))
  install.packages("dsBaseClient", repos = c(dsr, cran))        # base DataSHIELD client

# dsOMOPClient 2.0.0 from GitHub (pulls its CRAN imports automatically).
if (!have("remotes")) install.packages("remotes", repos = cran)
need_omop <- !have("dsOMOPClient") ||
  as.character(utils::packageVersion("dsOMOPClient")) != "2.0.0"
if (need_omop) {
  remotes::install_github("isglobal-brge/dsOMOPClient", ref = "2.0.0",
                          upgrade = "never")
}

cat("Client packages ready:\n")
for (p in c("DSI", "DSOpal", "dsBaseClient", "dsOMOPClient")) {
  v <- tryCatch(as.character(utils::packageVersion(p)), error = function(e) "MISSING")
  cat(sprintf("  %-13s %s\n", p, v))
}
