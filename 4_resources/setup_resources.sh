#!/usr/bin/env bash
# Step 4 — Create the dsOMOP CDM resource on each federated Opal site.
#
# Thin wrapper around create_resources.R: on each of the three sites it provisions
# (1) a resource-only Opal project and (2) one OMOP CDM resource of dsOMOP v2
# format "omop.dbi.db" whose URL points the Rock session at that site's PostgreSQL
# over the Docker network. Ports / credentials are hardcoded in create_resources.R.
#
# This step talks to the Opal REST API with R's opalr package (installed on first
# run if missing) — it does NOT need Docker itself, only the sites from steps 2/3.
#
# Prerequisites:
#   - Steps 2 and 3 done (sites up, databases seeded).
#   - R available on PATH (Rscript). Install R from https://cran.r-project.org/.
#
# Usage:
#   bash 4_resources/setup_resources.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript not found. Install R (https://cran.r-project.org/) and retry." >&2
  exit 1
fi

exec Rscript "$SCRIPT_DIR/create_resources.R"
