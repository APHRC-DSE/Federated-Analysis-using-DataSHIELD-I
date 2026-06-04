# Federated Analysis using DataSHIELD — reproducibility package

Reproducibility package for the methods paper **“Federated Analysis
using DataSHIELD”**. It stands up a **fully local, three-site
federation** and runs a real federated analysis over **OMOP CDM** data
using **DataSHIELD** and
[**dsOMOP**](https://github.com/isglobal-brge/dsOMOP) **v2.0.0**.

The synthetic OHDSI **GiBleed** cohort (2 694 persons) is **sharded by
person** across three independent sites — `aphrc`, `dgh`, `iressef` — so
that every person and all of their records live on exactly one site. The
client never sees patient-level data: dsOMOP returns only
disclosure-checked aggregates, and the one person-level table it
extracts is analysed *in place* on each server by standard
`dsBaseClient`. The pooled person count across the three shards
reconstructs the whole cohort (**2 694**) without any site holding more
than its own shard.

## Architecture

                             DataSHIELD client (host R)
                      DSI · DSOpal · dsBaseClient · dsOMOPClient
                                       │
             ┌─────────────────────────┼─────────────────────────┐
             │ login(profile = "omop") │                          │
       ┌─────▼─────┐              ┌─────▼─────┐              ┌─────▼─────┐
       │  aphrc    │              │   dgh     │              │  iressef  │
       │  Opal     │              │   Opal    │              │   Opal    │
       │  + Rock   │              │  + Rock   │              │  + Rock   │   Rock "omop" profile
       │  "omop"   │              │  "omop"   │              │  "omop"   │   = dsOMOP image
       └─────┬─────┘              └─────┬─────┘              └─────┬─────┘
             │ resource omop_demo.gibleed (format omop.dbi.db)     │
       ┌─────▼─────┐              ┌─────▼─────┐              ┌─────▼─────┐
       │ PostgreSQL│              │ PostgreSQL│              │ PostgreSQL│   alias "omopdb:5432"
       │  cdm      │              │  cdm      │              │  cdm      │   on the site's
       │ person%3=0│              │ person%3=1│              │ person%3=2│   docker network
       └───────────┘              └───────────┘              └───────────┘

Each site is an independent
[easy-opal](https://github.com/isglobal-brge/easy-opal) instance:
**Opal + MongoDB**, plus a **Rock** R-server profile named `omop` built
from the dsOMOP image. A **self-managed PostgreSQL** holds that site’s
OMOP CDM shard and is attached to the site’s Docker network under the
alias `omopdb`, so each Rock session resolves `omopdb:5432` to *its own*
database. A DataSHIELD **resource** (`omop_demo.gibleed`, format
`omop.dbi.db`) tells dsOMOP how to open it. The same resource definition
is therefore valid on every site.

## Prerequisites

| Tool | Version | Used for |
|----|----|----|
| Docker | Engine ≥ 20.10 with **Compose v2** (tested 29.0.1) | Opal, Rock, MongoDB, PostgreSQL containers |
| Python | ≥ 3.11 | runs easy-opal |
| R | ≥ 4.1 (tested 4.5.2) | the DataSHIELD client packages |

> **Apple Silicon / arm64:** the upstream Opal, Rock and dsOMOP images
> are published for **`linux/amd64` only**, so they run under emulation
> (slower, but functional). The dsOMOP image in `docker/` is built for
> amd64 for this reason.

## Quick start

Run the five steps in order. Each step reads the machine-specific values
the previous one wrote to `sites.env` (gitignored), so there is nothing
to configure by hand.

``` bash
bash 1_setup/install_easy_opal.sh        # install easy-opal into ./.venv
source .venv/bin/activate                #   (puts easy-opal on PATH)
bash 2_opal_stacks/setup_sites.sh        # 3 × Opal + Rock("omop") + MongoDB
bash 3_databases/setup_databases.sh      # 3 × PostgreSQL, GiBleed sharded by person
bash 4_resources/setup_resources.sh      # the dsOMOP CDM resource on each site
bash 5_client/setup_client.sh            # install client stack + run the analysis
```

Open any site in a browser (URL printed by step 2, also in `sites.env`)
and log in as `administrator` / `password` to inspect it.

## What you should see

Step 3 prints each site’s shard size and step 5 prints federated
results. The person shards partition the cohort:

| Site       | `person_id % 3` | Persons   |
|------------|-----------------|-----------|
| `aphrc`    | 0               | 889       |
| `dgh`      | 1               | 878       |
| `iressef`  | 2               | 927       |
| **pooled** | —               | **2 694** |

Step 5 walks through: schema exploration, federated row/person counts
(per site and pooled), most-prevalent conditions, numeric value
quantiles (drug-exposure days-supply), and finally a server-side
person-level extraction analysed with `dsBaseClient` (`ds.dim`,
`ds.colnames`, `ds.mean`, `ds.table`).

## How privacy is enforced

Nothing patient-level ever leaves a site. **dsOMOP v2 performs its own
statistical disclosure control** on every server response:

- the standard DataSHIELD **`nfilter.*`** thresholds (minimum
  cell/subset counts, maximum factor levels, string-length limits),
  published with the package onto the Rock `omop` profile, plus dsOMOP’s
  own `dsomop.*` opt-outs;
- a **mandatory, non-disableable identifier strip** applied to every
  extracted table before it enters the DataSHIELD session.

dsOMOP v2 does **not** use `datashield.privacyControlLevel` (the
`permissive/banana/avocado/...` hierarchy is a *dsBase* mechanism it
does not rely on), so no privacy level needs to be set — see
[`4_resources/README.md`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/4_resources/README.md).

## Software versions (manifest)

Pinned for reproducibility. Server-side packages come from the dsOMOP
image
([`docker/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/docker/));
client-side packages are installed by step 5.

| Component | Version | Source / pin |
|----|----|----|
| easy-opal | 2.1.0 | `pip install easy-opal==2.1.0` (step 1) |
| Opal | 5.5.1 | `obiba/opal` |
| MongoDB | 8.2.4 | `mongo` |
| Rock server | 6.3.5 | base image `datashield/rock-base:6.3.5-R4.5.3` |
| R (server) | 4.5.3 | in `rock-base` |
| dsBase (server) | 6.3.5 | bundled in `rock-base` 6.3.5 |
| dsOMOP (server) | 2.0.0 | `isglobal-brge/dsOMOP@2.0.0` (in the image) |
| OS (images) | Ubuntu 24.04 LTS (Noble) | base of the Rock/Opal images |
| PostgreSQL | 16 | `postgres:16` |
| OMOP CDM | 5.3 | DDL + GiBleed (see provenance) |
| R (client) | 4.5.2 | host R |
| DSI | 1.8.0 | CRAN |
| DSOpal | 1.5.0 | CRAN |
| dsBaseClient | 6.3.4 | cran.datashield.org |
| dsOMOPClient | 2.0.0 | `isglobal-brge/dsOMOPClient@2.0.0` |
| opalr | 3.5.2 | CRAN |

dsOMOP image: `davidsarrat/rock-dsomop-dswb-reproducibility:2.0.0`
(linux/amd64).

## Data provenance & licensing

- **GiBleed** synthetic OMOP CDM 5.3 dataset — OHDSI/EunomiaDatasets @
  `3efd533` (Apache-2.0). 2 694 synthetic persons; no real patient data.
- **OMOP CDM 5.3 DDL** — OHDSI/CommonDataModel @ `d83d48c` (Apache-2.0).

This repository’s own code is released under the **MIT License** (see
[`LICENSE`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/LICENSE)).

## Repository layout

| Path | What it does |
|----|----|
| [`1_setup/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/1_setup/) | Install easy-opal (pinned) into `./.venv`. |
| [`2_opal_stacks/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/2_opal_stacks/) | Stand up the three Opal + Rock + MongoDB sites. |
| [`3_databases/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/3_databases/) | Seed each site’s PostgreSQL with the GiBleed shard. |
| [`4_resources/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/4_resources/) | Register the dsOMOP CDM resource on each site. |
| [`5_client/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/5_client/) | Install the client stack and run the federated analysis. |
| [`docker/`](https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/docker/) | The Rock + dsOMOP image used by the `omop` profile. |
| `sites.env` | Generated by steps 2–4; machine-specific, **gitignored**. |

## Reproducibility notes

- **Opal / MongoDB pinning.** `2_opal_stacks/setup_sites.sh` defaults
  `OPAL_VERSION` / `MONGO_VERSION` to the manifest versions (Opal 5.5.1,
  MongoDB 8.2.4); override either env var to use a different version.
- **Plain HTTP** is used (`OPAL_SSL=none`) because everything is on
  `localhost`, which keeps the client reproducible with no certificates.
  Set `OPAL_SSL=self-signed` for HTTPS.
- **Demo credentials are intentional** and public: Opal `administrator`
  / `password`, PostgreSQL `postgres` / `postgres`. Do not reuse them
  anywhere real.
- **Ports are auto-selected** from free blocks (Opal near 48080,
  PostgreSQL near
  45432. and recorded in `sites.env`; the dsOMOP resource never uses a
         host port.

## Citation

If you use this package, please cite the paper *“Federated Analysis
using DataSHIELD”* (citation details to be added on publication).
