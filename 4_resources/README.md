# Step 4 — Register the dsOMOP CDM resource on each site

This step tells each Opal site **where its OMOP data lives** by creating a
DataSHIELD **resource** that the dsOMOP server package (running in the `omop`
Rock profile) knows how to open. It uses the Opal REST API through R's
[`opalr`](https://cran.r-project.org/package=opalr) package and reads everything
it needs from **`../sites.env`** (written by steps 2 and 3).

## Prerequisites

- **Steps 2 and 3 done** — the three sites are up and each has its own seeded
  PostgreSQL on the site's Docker network (`../sites.env` exists with the
  `*_OPAL_URL` and `PG_*` entries).
- **R available** (`Rscript` on `PATH`). `opalr` is installed automatically on
  first run if it is missing. Get R from <https://cran.r-project.org/>.

> Docker is **not** used directly in this step — it only talks HTTP to the Opal
> servers from step 2.

## Run

```bash
bash 4_resources/setup_resources.sh
```

Override the project or resource name if you like:

```bash
OPAL_PROJECT=omop_demo OPAL_RESOURCE=gibleed \
  bash 4_resources/setup_resources.sh
```

## What it does, per site

1. **Ensures a resource-only Opal project** (default `omop_demo`). No storage
   database is attached — dsOMOP reads through the resource, not Opal tables.
2. **(Re)creates one OMOP CDM resource** (default name `gibleed`) of dsOMOP v2
   format **`omop.dbi.db`**, pointing the Rock session at that site's PostgreSQL.

The chosen resource path is written back to `../sites.env` as
`OPAL_RESOURCE_PATH` (e.g. `omop_demo.gibleed`) so step 5 picks it up.

No DataSHIELD privacy-control level is set here — see
[Privacy and disclosure control](#privacy-and-disclosure-control) below.

## The dsOMOP v2 resource format (important)

> ⚠️ The public dsOMOP **README still documents the old v1 format**
> (`type omop.cdm.db`, `opal.resource_extension_create(provider='dsOMOP',
> factory='omop-cdm-db', ...)`). **dsOMOP 2.0.0 does not use that.** This step
> follows the actual 2.0.0 source (`R/resource.R`).

A v2 resource is an ordinary `resourcer` resource that the dsOMOP resolver
matches **by `format == "omop.dbi.db"`**. All connection details ride inside the
URL, base64url-encoded so Opal's R URL parser never sees a `?`, `&`, or `=`:

```
omop+dbi:///B64:<base64url( JSON )>

JSON = {"dbms":"postgresql","host":"omopdb","port":5432,
        "database":"omop","cdm_schema":"cdm","vocabulary_schema":"cdm"}
```

- **`host` / `port` are Docker-internal** — the network alias `omopdb` and the
  in-container port `5432` from step 3, **not** a host port. The same resource
  definition is therefore valid on every site; each Rock session resolves
  `omopdb` to its own site's database.
- **Credentials are not in the URL.** The DB user/password are stored as the
  resource's `identity`/`secret` (here `postgres`/`postgres`).

## Privacy and disclosure control

**dsOMOP 2.0.0 does not use `datashield.privacyControlLevel` at all.** The
`permissive > banana > avocado > carrot > non-permissive` hierarchy is a
*dsBase* mechanism (it gates dsBase functions such as `ds.dataFrameSubset` /
`ds.reShape`). dsOMOP v2 neither depends on dsBase nor reads that option, so its
operations — **including data extraction** (`ds.omop.plan.execute`) — behave the
same at every level. (The stale v1 README that mentions `permissive`/`banana`
predates this rewrite.)

Instead, dsOMOP v2 enforces its **own** statistical disclosure control on every
server response, regardless of the level:

- the standard DataSHIELD **`nfilter.*`** thresholds (minimum cell/subset counts,
  maximum factor levels, string limits — published with the package onto the
  profile), plus dsOMOP's own `dsomop.*` opt-outs (e.g. `allow_sensitive_columns`);
- a **mandatory, non-disableable identifier strip** applied to every extracted
  table before it is assigned into the DataSHIELD session.

The only thing that actually gates extraction is that dsOMOP's **assign methods
must be published on the Rock `omop` profile** — which the dsOMOP image and
easy-opal handle when the profile is created in step 2. Nothing to set here.

## Configuration (environment variables)

| Var | Default | Purpose |
|-----|---------|---------|
| `OPAL_PROJECT` | `omop_demo` | Opal project that holds the resource. |
| `OPAL_RESOURCE` | `gibleed` | Resource name (same on every site). |
| `SITES_ENV` | `../sites.env` | Where to read site URLs + DB settings from. |

Connection details (`PG_HOST_ALIAS`, `PG_INTERNAL_PORT`, `PG_DATABASE`,
`PG_SCHEMA`, `PG_USER`, `PG_PASSWORD`) and the site URLs are **read from
`sites.env`**, not set here.

## Verify

Open any site URL from `sites.env`, log in as `administrator` / `password`, open
project **`omop_demo` → Resources**, and confirm a `gibleed` resource of type
`omop.dbi.db`. Or from R:

```r
library(opalr)
o <- opal.login("administrator", "password", "http://localhost:48080")  # an *_OPAL_URL
opal.resources(o, "omop_demo")
opal.logout(o)
```

## Next

Step 5 logs the DataSHIELD client into all three sites (profile `omop`), attaches
this resource with `ds.omop.connect()`, and runs the federated analysis.
