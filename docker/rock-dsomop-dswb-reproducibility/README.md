# Rock + dsOMOP image (`rock-dsomop-dswb-reproducibility`)

A Rock R server image for the federated DataSHIELD sites. It extends the upstream
`datashield/rock-base` (which already bundles the Rock server and `dsBase`) with
the OMOP CDM layer:

- `dsOMOP` **v2.0.0** (server-side, from `isglobal-brge/dsOMOP`)
- `resourcer`, `DBI`, `RPostgres` (and `R6`, `jsonlite`, `arrow` pulled by dsOMOP)

In step 2 this image is registered as an easy-opal **Rock profile** on each of the
three Opal sites, so the federated R sessions can read OMOP CDM resources.

## Platform note (amd64 only)

Every upstream Rock base on Docker Hub (`datashield/rock-base`, `obiba/rock`,
`brgelab/rock-dsomop`) is published for **`linux/amd64` only** — there is no
`arm64` variant. Therefore:

- The image is built for `linux/amd64`.
- It runs **natively on Linux/amd64 servers** (the usual reviewer environment).
- On **Apple Silicon** it runs **emulated** (QEMU via Docker Desktop) — slower but
  functional. This is why it can be built on a Mac and still run on Linux.

## Build and push

Set `IMAGE` to your Docker Hub repository, then:

```bash
docker login
IMAGE=youruser/rock-dsomop-dswb-reproducibility ./build_and_push.sh
```

The default tag is `2.0.0` and it pins `DSOMOP_REF=2.0.0` (the dsOMOP git tag).
Until that tag exists, build against the commit instead:

```bash
IMAGE=youruser/rock-dsomop-dswb-reproducibility DSOMOP_REF=fe566b98f30b2daebce0d6acfffbeadcf166b031 ./build_and_push.sh
```

## Build arguments

| Arg | Default | Purpose |
|-----|---------|---------|
| `ROCK_BASE`  | `datashield/rock-base:6.3.5-R4.5.3` | Upstream Rock base (bundles Rock server + dsBase + R). |
| `DSOMOP_REF` | `2.0.0` | Git tag or commit SHA of `isglobal-brge/dsOMOP` to install. |

## Use in step 2

After pushing, register it as a profile on each site (see `2_opal_stacks/`):

```bash
easy-opal -i aphrc profile add --image youruser/rock-dsomop-dswb-reproducibility --tag 2.0.0 --name omop
easy-opal -i aphrc restart
```
