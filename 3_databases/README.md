# Step 3 — Seed each site with a synthetic OMOP CDM database

Each of the three sites from step 2 gets its **own** PostgreSQL database holding a
slice of the OHDSI **GiBleed** synthetic dataset (OMOP CDM **v5.3**, 2694 persons).
This simulates three institutions that each hold a disjoint set of patients — the
setting DataSHIELD is built for.

## Prerequisites

- **Step 2 done** — the three stacks are up and the `omop` Rock profile is running.
- **Docker running**, plus `curl` and `unzip` on the host.

## Run

```bash
bash 3_databases/setup_databases.sh
```

## What it does, per site

1. Starts a self-managed PostgreSQL container **`omopdb-<site>`** with fixed
   credentials `postgres` / `postgres` and database `omop`.
2. Attaches it to that site's easy-opal Docker network with the **network alias
   `omopdb`**, so the site's Rock `omop` profile reaches it at **`omopdb:5432`** —
   a Docker-internal address that does not depend on any host port.
3. Creates the OMOP CDM 5.3 schema (`cdm`) and loads the GiBleed CSVs.
4. **Shards by person**: keeps only persons with `person_id % 3 == <site index>`,
   and deletes the other persons' rows from every person-linked table.

### How the data is split

| Table kind | Has `person_id`? | Treatment |
|------------|------------------|-----------|
| Clinical (person, visit_occurrence, condition_occurrence, drug_exposure, measurement, …) | yes | **Sharded** — a person and *all* their records live on exactly one site. |
| Vocabulary / metadata (concept, vocabulary, location, care_site, provider, cdm_source, …) | no | **Replicated** to all three, so every site can resolve concepts. |

The split is deterministic (`person_id % 3`), so it is identical on every machine:

| Site | Keeps `person_id % 3 ==` | Persons |
|------|--------------------------|---------|
| aphrc   | 0 | 889 |
| dgh     | 1 | 878 |
| iressef | 2 | 927 |

> A handful of GiBleed CSVs have no matching table in the core CDM 5.3 DDL
> (e.g. `COHORT`, `COHORT_ATTRIBUTE`); these are skipped with a log line.

## Why a self-managed Postgres (not easy-opal's `--database`)

dsOMOP reaches its data through an Opal **resource** — a direct DBI/RPostgres
connection opened *inside* the Rock R session — not through Opal's own system
databases (those hold Opal's users/config). So the database only needs to sit on
the same Docker network as Rock with **known** credentials. easy-opal's managed DB
auto-generates its password, which would make step 4's resource definition
non-reproducible; forcing `postgres`/`postgres` here keeps it turnkey.

## Configuration (environment variables)

| Var | Default | Purpose |
|-----|---------|---------|
| `PG_VERSION` | `16` | PostgreSQL image tag. |
| `PG_USER` / `PG_PASSWORD` | `postgres` / `postgres` | DB credentials (intentional for this public demo). |
| `PG_DB` | `omop` | Database name. |
| `PG_SCHEMA` | `cdm` | Schema the CDM tables live in. |
| `PG_ALIAS` | `omopdb` | Docker network alias the resource points at. |
| `PG_PORT_BASE` | `45432` | First host port to publish (inspection only). |
| `GIBLEED_URL` / `DDL_URL` | pinned | Synthetic data + CDM DDL sources (override to re-pin). |

## What it writes to `sites.env`

A PostgreSQL block is appended (and refreshed on re-run) for step 4 to read:

```
PG_USER=postgres
PG_PASSWORD=postgres
PG_DATABASE=omop
PG_SCHEMA=cdm
PG_HOST_ALIAS=omopdb
PG_INTERNAL_PORT=5432
APHRC_PG_PORT=45432       # host port — inspection only; Rock uses the alias
DGH_PG_PORT=45433
IRESSEF_PG_PORT=45434
```

## Inspect

```bash
# host port from sites.env (e.g. APHRC_PG_PORT)
PGPASSWORD=postgres psql -h localhost -p 45432 -U postgres -d omop \
  -c 'select count(*) from cdm.person;'
```

## Re-running

The script recreates each `omopdb-<site>` container **and its volume** from scratch,
so re-running gives a clean, identical load. Run it again any time after step 2.

## Provenance (pinned, Apache-2.0)

- GiBleed CDM 5.3 CSVs — [`OHDSI/EunomiaDatasets`](https://github.com/OHDSI/EunomiaDatasets) @ `3efd533`
- OMOP CDM 5.3 PostgreSQL DDL — [`OHDSI/CommonDataModel`](https://github.com/OHDSI/CommonDataModel) @ `d83d48c`

## Next

Step 4 registers an Opal project + dsOMOP resource on each site, pointing at
`omopdb:5432` with these credentials.
