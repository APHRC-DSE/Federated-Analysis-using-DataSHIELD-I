#!/usr/bin/env bash
# Step 3 — Seed each site with its own OMOP CDM PostgreSQL database (synthetic data).
#
# For every site brought up in step 2 (aphrc, dgh, iressef) this script:
#   - starts a self-managed PostgreSQL container "omopdb-<site>" (postgres/postgres),
#   - attaches it to that site's easy-opal Docker network with the network alias
#     "omopdb", so the site's Rock "omop" profile resolves it as host "omopdb:5432"
#     (a Docker-internal address — independent of whichever host port was free),
#   - creates the OMOP CDM v5.3 schema and loads the OHDSI **GiBleed** synthetic
#     dataset (2694 persons),
#   - shards the data across the three sites by person: a person and ALL of their
#     person-linked records live on exactly one site (person_id % 3 == site index).
#     Vocabulary / metadata tables (concept, vocabulary, location, ...) carry no
#     person_id and are replicated to all three so each site can resolve concepts.
#
# Why self-managed Postgres (not easy-opal's --database): dsOMOP reaches its data
# through an Opal *resource* (a direct DBI/RPostgres connection made inside the Rock
# R session), NOT through Opal's own system databases. So the DB just needs to be on
# the same Docker network as Rock, with known credentials. easy-opal's managed DB
# auto-generates its password; here we force postgres/postgres (intentional, public
# demo) so step 4's resource definition is fully reproducible.
#
# Host ports are published only so a human can inspect the data with psql/a GUI;
# Rock never uses them. The chosen ports + shared credentials are appended to
# ../sites.env for step 4 (resources) to read.
#
# Data provenance (pinned for reproducibility):
#   - GiBleed CDM 5.3 CSVs : OHDSI/EunomiaDatasets @ 3efd533  (Apache-2.0)
#   - OMOP CDM 5.3 DDL     : OHDSI/CommonDataModel @ d83d48c  (Apache-2.0)
#
# Prerequisites:
#   - Step 2 done: the three stacks are up and the "omop" Rock profile is running.
#   - Docker running; curl + unzip available.
#
# Usage:
#   bash 3_databases/setup_databases.sh
set -euo pipefail

SITES=(aphrc dgh iressef)

PG_VERSION="${PG_VERSION:-16}"           # PostgreSQL image tag (multi-arch: native on arm64 too)
PG_USER="${PG_USER:-postgres}"
PG_PASSWORD="${PG_PASSWORD:-postgres}"   # intentional for this public demo
PG_DB="${PG_DB:-omop}"
PG_SCHEMA="${PG_SCHEMA:-cdm}"
PG_ALIAS="${PG_ALIAS:-omopdb}"           # docker network alias the Rock 'omop' profile resolves

PG_PORT_BASE="${PG_PORT_BASE:-45432}"    # first candidate host port (inspection only)
PG_PORT_STEP="${PG_PORT_STEP:-10}"
PG_PORT_TRIES="${PG_PORT_TRIES:-50}"

# Pinned synthetic-data + schema sources.
GIBLEED_URL="${GIBLEED_URL:-https://raw.githubusercontent.com/OHDSI/EunomiaDatasets/3efd533eb95a41a56d5b0758b0d7c8fa57e1303e/datasets/GiBleed/GiBleed_5.3.zip}"
DDL_URL="${DDL_URL:-https://raw.githubusercontent.com/OHDSI/CommonDataModel/d83d48c2ba1b641879c33958903f630318421cb8/inst/ddl/5.3/postgresql/OMOPCDM_postgresql_5.3_ddl.sql}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITES_ENV="$REPO_ROOT/sites.env"
CACHE="$SCRIPT_DIR/.cache"

# --- preconditions ---------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running. Start Docker and retry." >&2
  exit 1
fi
for tool in curl unzip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: '$tool' is required but not found." >&2; exit 1; }
done
if [ ! -f "$SITES_ENV" ]; then
  echo "ERROR: $SITES_ENV not found. Run step 2 first: bash 2_opal_stacks/setup_sites.sh" >&2
  exit 1
fi
# Rock profile name from step 2 (used to find each site's Rock container). Read it
# directly rather than sourcing sites.env, so a prior run's PG_* lines can't override
# this invocation's settings.
OPAL_PROFILE="$(grep -E '^OPAL_PROFILE=' "$SITES_ENV" | tail -1 | cut -d= -f2-)"
OPAL_PROFILE="${OPAL_PROFILE:-omop}"

# --- find a free contiguous block of host ports (same probe as step 2) -----
port_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
find_block() {
  local base="$1" count="$2" step="$3" tries="$4" try b k ok
  for ((try = 0; try < tries; try++)); do
    b=$((base + try * step)); ok=1
    for ((k = 0; k < count; k++)); do
      port_free $((b + k)) || { ok=0; break; }
    done
    [ "$ok" -eq 1 ] && { echo "$b"; return 0; }
  done
  return 1
}
if ! PG_BLOCK_BASE="$(find_block "$PG_PORT_BASE" "${#SITES[@]}" "$PG_PORT_STEP" "$PG_PORT_TRIES")"; then
  echo "ERROR: no ${#SITES[@]} free contiguous ports near $PG_PORT_BASE (tried $PG_PORT_TRIES blocks)." >&2
  exit 1
fi

# --- fetch + prepare the data (cached under .cache/) -----------------------
mkdir -p "$CACHE"
ZIP="$CACHE/GiBleed_5.3.zip"
CSV_DIR="$CACHE/GiBleed_5.3"
DDL_RAW="$CACHE/OMOPCDM_postgresql_5.3_ddl.sql"
DDL_FILE="$CACHE/ddl_${PG_SCHEMA}.sql"

[ -f "$ZIP" ]    || { echo "==> downloading GiBleed CDM 5.3 dataset"; curl -fsSL "$GIBLEED_URL" -o "$ZIP"; }
[ -d "$CSV_DIR" ] || unzip -oq "$ZIP" -x '__MACOSX/*' -d "$CACHE"
[ -f "$DDL_RAW" ] || { echo "==> downloading OMOP CDM 5.3 PostgreSQL DDL"; curl -fsSL "$DDL_URL" -o "$DDL_RAW"; }
# Substitute the schema placeholder once; reused by every site.
sed "s/@cdmDatabaseSchema/${PG_SCHEMA}/g" "$DDL_RAW" > "$DDL_FILE"

echo "==> PostgreSQL host ports: ${PG_BLOCK_BASE}..$((PG_BLOCK_BASE + ${#SITES[@]} - 1))  (inspection only)"

# --- refresh the step-3 block in sites.env ---------------------------------
MARK="# === step 3 (databases) — appended by 3_databases/setup_databases.sh ==="
# Drop any previous step-3 block (everything from the marker onward) so re-runs don't duplicate.
awk -v m="$MARK" 'index($0,m){exit} {print}' "$SITES_ENV" > "$SITES_ENV.tmp" && mv "$SITES_ENV.tmp" "$SITES_ENV"
{
  echo ""
  echo "$MARK"
  echo "PG_USER=${PG_USER}"
  echo "PG_PASSWORD=${PG_PASSWORD}"
  echo "PG_DATABASE=${PG_DB}"
  echo "PG_SCHEMA=${PG_SCHEMA}"
  echo "PG_HOST_ALIAS=${PG_ALIAS}"      # host the dsOMOP resource points at (Docker-internal)
  echo "PG_INTERNAL_PORT=5432"
} >> "$SITES_ENV"

# --- seed each site --------------------------------------------------------
idx=0
for site in "${SITES[@]}"; do
  port=$((PG_BLOCK_BASE + idx))
  PGC="omopdb-${site}"
  ROCKC="${site}-${OPAL_PROFILE}"
  echo
  echo "==> [${site}] (keeps persons where person_id % 3 == ${idx})"

  # Discover the site's Docker network from its running Rock container.
  net="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$ROCKC" 2>/dev/null | awk 'NF{print; exit}')"
  if [ -z "$net" ]; then
    echo "ERROR: container '$ROCKC' not found / has no network. Is step 2 done with profile '$OPAL_PROFILE'?" >&2
    exit 1
  fi

  # Fresh database container each run (our own synthetic data — safe to recreate).
  docker rm -f "$PGC" >/dev/null 2>&1 || true
  docker volume rm "${PGC}-data" >/dev/null 2>&1 || true

  echo "    starting ${PGC} on network ${net} (alias ${PG_ALIAS}, host port ${port})"
  docker run -d --name "$PGC" \
    --network "$net" --network-alias "$PG_ALIAS" \
    -e POSTGRES_USER="$PG_USER" -e POSTGRES_PASSWORD="$PG_PASSWORD" -e POSTGRES_DB="$PG_DB" \
    -p "${port}:5432" \
    -v "${PGC}-data:/var/lib/postgresql/data" \
    "postgres:${PG_VERSION}" >/dev/null

  # Wait until Postgres accepts connections.
  ready=0
  for _ in $(seq 1 60); do
    if docker exec "$PGC" pg_isready -U "$PG_USER" -d "$PG_DB" >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
  done
  [ "$ready" -eq 1 ] || { echo "ERROR: ${PGC} did not become ready in time." >&2; exit 1; }

  # Create the schema + all CDM 5.3 tables.
  docker exec -i "$PGC" psql -v ON_ERROR_STOP=1 -qU "$PG_USER" -d "$PG_DB" \
    -c "CREATE SCHEMA IF NOT EXISTS ${PG_SCHEMA};"
  docker exec -i "$PGC" psql -v ON_ERROR_STOP=1 -qU "$PG_USER" -d "$PG_DB" < "$DDL_FILE"

  # Which tables actually exist (GiBleed ships a few CSVs with no 5.3 table, e.g. COHORT).
  existing="$(docker exec "$PGC" psql -tAqU "$PG_USER" -d "$PG_DB" \
    -c "SELECT tablename FROM pg_tables WHERE schemaname='${PG_SCHEMA}';")"
  table_exists() { printf '%s\n' "$existing" | grep -qx "$1"; }

  # Load every CSV, then shard person-linked tables to this site.
  echo "    loading + sharding GiBleed"
  for f in "$CSV_DIR"/*.csv; do
    t="$(basename "$f" .csv | tr '[:upper:]' '[:lower:]')"
    table_exists "$t" || { echo "      - skip ${t} (no ${PG_SCHEMA} table)"; continue; }
    # Column list = CSV header, lowercased, in file order (matches the data columns).
    # Double-quote each name so reserved words are valid (e.g. note_nlp has "offset").
    cols="$(head -1 "$f" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
    qcols="$(printf '%s' "$cols" | awk -F, '{for(i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?",":""), $i}')"
    docker exec -i "$PGC" psql -v ON_ERROR_STOP=1 -qU "$PG_USER" -d "$PG_DB" \
      -c "\copy ${PG_SCHEMA}.${t} (${qcols}) FROM STDIN WITH (FORMAT csv, HEADER true)" < "$f"
    case ",${cols}," in
      *,person_id,*)
        docker exec "$PGC" psql -v ON_ERROR_STOP=1 -qU "$PG_USER" -d "$PG_DB" \
          -c "DELETE FROM ${PG_SCHEMA}.${t} WHERE person_id % 3 <> ${idx};" ;;
    esac
  done

  n_persons="$(docker exec "$PGC" psql -tAqU "$PG_USER" -d "$PG_DB" \
    -c "SELECT count(*) FROM ${PG_SCHEMA}.person;")"
  echo "    ${site}: ${n_persons} persons"

  key="$(echo "$site" | tr '[:lower:]' '[:upper:]')_PG_PORT"
  echo "${key}=${port}" >> "$SITES_ENV"
  idx=$((idx + 1))
done

echo
echo "==> All databases seeded. Appended PostgreSQL settings to ${SITES_ENV}."
echo "Inspect a site, e.g.:  PGPASSWORD=${PG_PASSWORD} psql -h localhost -p ${PG_BLOCK_BASE} -U ${PG_USER} -d ${PG_DB} -c 'select count(*) from ${PG_SCHEMA}.person;'"
echo "Next: create the Opal projects + dsOMOP resources (step 4)."
