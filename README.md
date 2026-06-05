# Federated Analysis using DataSHIELD — reproducibility package

This repository is the reproducibility package for the methods paper
**"Federated Analysis using DataSHIELD"**. It is built around a
[**bookdown**](https://bookdown.org/) book that doubles as a **step-by-step
tutorial**: it walks you through standing up a **fully local, three-site
federation** and then runs a real federated analysis over **OMOP CDM** data
using **DataSHIELD** and
[**dsOMOP**](https://github.com/isglobal-brge/dsOMOP) **v2.0.0**.

> **Read the book:** the rendered tutorial + analysis lives at
> **<https://aphrc-dse.github.io/Federated-Analysis-using-DataSHIELD-I/>**. Its
> first part reproduces the federation one step at a time; its second part
> explores the catalogue, extracts a fused person-level table, describes it, and
> fits a federated logistic regression — every figure and table is the genuine
> result of executing the code against the three sites. The sources live in
> [`book/`](book/).

We **simulate three research centres on one machine** because real centre data
cannot leave its owner. In their place we load the synthetic OHDSI **GiBleed**
cohort (2 694 persons), **sharded by person** across the three sites — `aphrc`,
`dgh`, `iressef` — so every person and all of their records live on exactly one
site. The client never sees patient-level data: dsOMOP returns only
disclosure-checked aggregates, and the one person-level table it extracts is
analysed *in place* on each server with standard `dsBaseClient`.

## Architecture

Each site is an independent [easy-opal](https://github.com/isglobal-brge/easy-opal)
instance: **Opal + MongoDB**, plus a **Rock** R-server profile named `omop` built
from the dsOMOP image. A **self-managed PostgreSQL** holds that site's OMOP CDM
shard and is attached to the site's Docker network under the alias `omopdb`, so
each Rock session resolves `omopdb:5432` to *its own* database. A DataSHIELD
**resource** (`omop_demo.gibleed`, format `omop.dbi.db`) tells dsOMOP how to open
it — the same definition is valid on every site. The DataSHIELD client (host R:
DSI · DSOpal · dsBaseClient · dsOMOPClient) logs in to all three. The book's
**Overview** renders this as a diagram.

## Prerequisites

| Tool | Version | Used for |
|------|---------|----------|
| Docker | Engine ≥ 20.10 with **Compose v2** (tested 29.0.1) | Opal, Rock, MongoDB, PostgreSQL containers |
| Python | ≥ 3.11 | runs easy-opal |
| R | ≥ 4.1 (tested 4.5.2) | the DataSHIELD client packages and bookdown |

> **Apple Silicon / arm64:** the upstream Opal, Rock and dsOMOP images are
> published for **`linux/amd64` only**, so they run under emulation (slower, but
> functional). The dsOMOP image in `docker/` is built for amd64 for this reason.

## Quick start

Run the steps in order, then render the book. There is **nothing to configure by
hand**: ports, credentials and the resource path are hardcoded in the scripts
(Opal on `localhost:48080`–`48082`, password `password`). If a port is already
taken, edit the matching value in the script — see each step's `README.md`.

```bash
bash 1_setup/install_easy_opal.sh        # install easy-opal into ./.venv
source .venv/bin/activate                #   (puts easy-opal on PATH)
bash 2_opal_stacks/setup_sites.sh        # 3 × Opal + Rock("omop") + MongoDB
bash 3_databases/setup_databases.sh      # 3 × PostgreSQL, GiBleed sharded by person
bash 4_resources/setup_resources.sh      # the dsOMOP CDM resource on each site
Rscript 5_client/install_client.R        # install the DataSHIELD client packages
```

With the federation up, render the book (it connects to all three sites and runs
the analysis live):

```bash
cd book && Rscript -e 'bookdown::render_book("index.Rmd")'   # outputs to ../docs
```

The demo credentials are **intentional and public** (Opal `administrator` /
`password`, PostgreSQL `postgres` / `postgres`) — do not reuse them anywhere
real. Open any site at <http://localhost:48080> and log in as `administrator` /
`password` to inspect it. A standalone, book-free run of the same analysis is
available via `bash 5_client/setup_client.sh`.

## The person shards

The synthetic cohort is partitioned deterministically by `person_id`, so the
pooled person count reconstructs the whole cohort without any site holding more
than its own shard:

| Site | `person_id % 3` | Persons |
|------|-----------------|---------|
| `aphrc`   | 0 | 889 |
| `dgh`     | 1 | 878 |
| `iressef` | 2 | 927 |
| **pooled** | — | **2 694** |

## How privacy is enforced

Nothing patient-level ever leaves a site. **dsOMOP v2 performs its own
statistical disclosure control** on every server response — the standard
DataSHIELD `nfilter.*` thresholds plus a **mandatory, non-disableable identifier
strip** — so it does **not** rely on `datashield.privacyControlLevel` and no
privacy level needs to be set. Details in
[`4_resources/README.md`](4_resources/README.md).

## Software versions (manifest)

Pinned for reproducibility. Server-side packages come from the dsOMOP image
([`docker/`](docker/)); client-side packages are installed in step 5.

| Component | Version | Source / pin |
|-----------|---------|--------------|
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

dsOMOP image: `davidsarrat/rock-dsomop-dswb-reproducibility:2.0.0` (linux/amd64).

## Data provenance & licensing

- **GiBleed** synthetic OMOP CDM 5.3 dataset — OHDSI/EunomiaDatasets @ `3efd533`
  (Apache-2.0). 2 694 synthetic persons; no real patient data.
- **OMOP CDM 5.3 DDL** — OHDSI/CommonDataModel @ `d83d48c` (Apache-2.0).

This repository's own code is released under the **MIT License** (see
[`LICENSE`](LICENSE)).

## Repository layout

| Path | What it does |
|------|--------------|
| [`book/`](book/) | The bookdown tutorial + analysis (the main deliverable). |
| [`1_setup/`](1_setup/) | Install easy-opal (pinned) into `./.venv`. |
| [`2_opal_stacks/`](2_opal_stacks/) | Stand up the three Opal + Rock + MongoDB sites. |
| [`3_databases/`](3_databases/) | Seed each site's PostgreSQL with the GiBleed shard. |
| [`4_resources/`](4_resources/) | Register the dsOMOP CDM resource on each site. |
| [`5_client/`](5_client/) | Install the client stack and run the federated analysis. |
| [`docker/`](docker/) | The Rock + dsOMOP image used by the `omop` profile. |

## Citation

If you use this package, please cite the paper *"Federated Analysis using
DataSHIELD"* (citation details to be added on publication).
