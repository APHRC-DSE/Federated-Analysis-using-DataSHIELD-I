#!/usr/bin/env bash
# Step 4 — Create the dsOMOP CDM resource on each federated Opal site.
#
# Thin wrapper around create_resources.R: it provisions, on every site listed in
# ../sites.env, (1) a resource-only Opal project and (2) one OMOP CDM resource of
# dsOMOP v2 format "omop.dbi.db" whose URL points the Rock session at that site's
# PostgreSQL over the Docker network. The resource path it settles on is written
# back to ../sites.env (OPAL_RESOURCE_PATH) for step 5.
#
# This step talks to the Opal REST API with R's opalr package (installed on first
# run if missing) — it does NOT need Docker itself, only the sites from step 2/3.
#
# Prerequisites:
#   - Steps 2 and 3 done (sites up, databases seeded; ../sites.env present).
#   - R available on PATH (Rscript). Install R from https://cran.r-project.org/.
#
# Usage:
#   bash 4_resources/setup_resources.sh
#   OPAL_PROJECT=myproj OPAL_RESOURCE=myres bash 4_resources/setup_resources.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITES_ENV="$REPO_ROOT/sites.env"

if [ ! -f "$SITES_ENV" ]; then
  echo "ERROR: $SITES_ENV not found. Run steps 2 and 3 first:" >&2
  echo "  bash 2_opal_stacks/setup_sites.sh && bash 3_databases/setup_databases.sh" >&2
  exit 1
fi
if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript not found. Install R (https://cran.r-project.org/) and retry." >&2
  exit 1
fi

exec Rscript "$SCRIPT_DIR/create_resources.R"
