#!/usr/bin/env bash
# Step 5 — Run the federated DataSHIELD + dsOMOP analysis across the three sites.
#
# Installs the client stack (DSI, DSOpal, dsBaseClient, dsOMOPClient 2.0.0) on
# first run, then executes the analysis in run_analysis.R against the sites and
# resource recorded in ../sites.env by steps 2-4.
#
# Prerequisites:
#   - Steps 2, 3 and 4 done (../sites.env has *_OPAL_URL and OPAL_RESOURCE_PATH).
#   - R available on PATH (Rscript). Install R from https://cran.r-project.org/.
#
# Usage:
#   bash 5_client/setup_client.sh             # install (if needed) + analyse
#   SKIP_INSTALL=1 bash 5_client/setup_client.sh   # analyse only
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITES_ENV="$REPO_ROOT/sites.env"

if [ ! -f "$SITES_ENV" ]; then
  echo "ERROR: $SITES_ENV not found. Run steps 2-4 first." >&2
  exit 1
fi
if ! grep -qE '^OPAL_RESOURCE_PATH=' "$SITES_ENV"; then
  echo "ERROR: OPAL_RESOURCE_PATH missing from $SITES_ENV. Run step 4 first:" >&2
  echo "  bash 4_resources/setup_resources.sh" >&2
  exit 1
fi
if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR: Rscript not found. Install R (https://cran.r-project.org/) and retry." >&2
  exit 1
fi

if [ "${SKIP_INSTALL:-0}" != "1" ]; then
  echo "==> ensuring client packages (DSI, DSOpal, dsBaseClient, dsOMOPClient 2.0.0)"
  Rscript "$SCRIPT_DIR/install_client.R"
fi

echo "==> running federated analysis"
exec Rscript "$SCRIPT_DIR/run_analysis.R"
