# Step 2 — Stand up the three federated Opal + Rock sites

This step uses [**easy-opal**](https://github.com/isglobal-brge/easy-opal)
(installed in step 1) to deploy the three independent federated sites used in the
paper — **aphrc**, **dgh**, **iressef** — each a self-contained Opal + Rock + MongoDB
stack running in Docker.

## Prerequisites

- **Step 1 done** — `easy-opal` available (the script auto-activates `../.venv` if present).
- **Docker running** — the daemon must be up; the script checks and exits otherwise.
- **The dsOMOP Rock image.** `IMAGE` defaults to the published, public
  `davidsarrat/rock-dsomop-dswb-reproducibility`, so nothing is required here.
  To use your own, build & push from
  [`docker/rock-dsomop-dswb-reproducibility/`](../docker/rock-dsomop-dswb-reproducibility/)
  and override `IMAGE`.

## Run

```bash
bash 2_opal_stacks/setup_sites.sh
```

This uses the published image `davidsarrat/rock-dsomop-dswb-reproducibility:2.0.0`.
To use your own image instead:

```bash
IMAGE=youruser/rock-dsomop-dswb-reproducibility TAG=2.0.0 bash 2_opal_stacks/setup_sites.sh
```

## What it does, per site

1. **Creates an easy-opal instance** (`aphrc`, `dgh`, `iressef`) — three isolated
   stacks that can run side by side on one host.
2. **Runs `easy-opal setup`** bringing up Opal + MongoDB on a fixed localhost
   port (`48080` / `48081` / `48082`), with the Opal admin password set to `password`.
3. **Adds the dsOMOP Rock profile** named **`omop`** from `IMAGE:TAG`, *alongside*
   the upstream default `rock` profile (the default is left in place). The
   DataSHIELD client logs into profile `omop` in step 5.
4. **Restarts** the stack so the new profile is live.

### Ports are fixed (edit if one is taken)

The three sites are served on **fixed localhost ports**, hardcoded at the top of
the script and reused unchanged by steps 3–5 and the book:

| Site | URL |
|------|-----|
| aphrc   | `http://localhost:48080` |
| dgh     | `http://localhost:48081` |
| iressef | `http://localhost:48082` |

The script does a pre-flight check and stops with a clear message if one of these
ports is already in use. If that happens, edit `OPAL_PORTS` at the top of
`setup_sites.sh` to free ports — and change the matching values in steps 3–5 and
the book — then re-run. There is **no** `sites.env`: everything is hardcoded so the
setup is identical on every machine.

## Configuration (environment variables)

| Var | Default | Purpose |
|-----|---------|---------|
| `IMAGE` | `davidsarrat/rock-dsomop-dswb-reproducibility` | Public Docker Hub repo with the dsOMOP Rock image. |
| `TAG` | `2.0.0` | Image tag to register as the `omop` profile. |
| `OPAL_VERSION` / `MONGO_VERSION` | `5.5.1` / `8.2.4` | Pinned to the manifest versions; override either to upgrade. |

The sites, ports, profile name (`omop`) and admin password (`password`) are
hardcoded constants near the top of the script — edit them there if needed.

### Why HTTP (SSL off)

Everything here is `localhost`, so plain HTTP keeps the client reproducible on any
machine — no certificates to generate, no `ssl_verifypeer` handling in the R client.

## Verify

After it finishes, open any site's URL (e.g. <http://localhost:48080>) in a browser
and log in as `administrator` / `password`. Under **Administration → Profiles** you
should see both `rock` and `omop`.

## Next

Step 3 seeds the synthetic OMOP CDM databases; step 4 registers the dsOMOP
resources that point the Rock sessions at them.
