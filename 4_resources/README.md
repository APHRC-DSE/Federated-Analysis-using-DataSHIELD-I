# Step 4 — Register the dsOMOP CDM resource on each site

This step tells each Opal site **where its OMOP data lives** by creating a
DataSHIELD **resource** that the dsOMOP server package (running in the `omop`
Rock profile) knows how to open. It uses the Opal REST API through R's
[`opalr`](https://cran.r-project.org/package=opalr) package; all connection
details (site URLs, DB credentials) are **hardcoded** in `create_resources.R`,
matching the fixed values from steps 2 and 3.

## Prerequisites

- **Steps 2 and 3 done** — the three sites are up and each has its own seeded
  PostgreSQL on the site's Docker network.
- **R available** (`Rscript` on `PATH`). `opalr` is installed automatically on
  first run if it is missing. Get R from <https://cran.r-project.org/>.

> Docker is **not** used directly in this step — it only talks HTTP to the Opal
> servers from step 2.

## Run

```bash
bash 4_resources/setup_resources.sh
```

## What it does, per site

1. **Ensures a resource-only Opal project** (`omop_demo`). No storage database is
   attached — dsOMOP reads through the resource, not Opal tables.
2. **(Re)creates one OMOP CDM resource** (name `gibleed`) of dsOMOP v2 format
   **`omop.dbi.db`**, pointing the Rock session at that site's PostgreSQL.

The resource path is the fixed `omop_demo.gibleed`, which step 5 logs into directly.

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

## Configuration

Everything is **hardcoded** near the top of `create_resources.R`: the three site
URLs, the Opal credentials (`administrator` / `password`), the PostgreSQL
connection details (`omopdb:5432`, db `omop`, schema `cdm`, `postgres` / `postgres`)
and the project/resource names (`omop_demo` / `gibleed`). Edit them there if you
changed a port or name in steps 2–3.

## Verify

Open any site URL (e.g. <http://localhost:48080>), log in as `administrator` /
`password`, open
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
