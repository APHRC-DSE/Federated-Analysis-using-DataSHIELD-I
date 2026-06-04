# Step 1 — Install easy-opal

This package reproduces the federated DataSHIELD setup described in the paper
*"Federated Analysis using DataSHIELD"*. This first step installs
[**easy-opal**](https://github.com/isglobal-brge/easy-opal), the CLI used to
deploy the Opal + Rock servers in the later steps.

## Prerequisites

### Server setup (steps 1–4 — run on the host that will run the three sites)

| Tool   | Minimum version | Notes |
|--------|-----------------|-------|
| Python | **3.11**        | Required by easy-opal 2.1.0. Used only to install/run easy-opal. |
| Docker | Engine ≥ 20.10 with **Compose v2** (`docker compose`) | Runs the Opal, Rock, MongoDB and PostgreSQL containers. The daemon must be running for steps 2+. |

### Federated analysis (step 5 — run on the DataSHIELD client = the reviewer's computer)

| Tool | Minimum version | Notes |
|------|-----------------|-------|
| R    | **4.1** (recommended **4.4.x**, to match the Rock server's R) | Runs the DataSHIELD client packages (`DSI`, `DSOpal`, `dsBaseClient`, `dsOMOPClient`). |

> The client and the servers can be the same machine. The step 5 analysis script
> assumes the client is your local computer connecting to the three local Opal sites.

## Run

```bash
bash 1_setup/install_easy_opal.sh
```

This creates a virtual environment at `.venv/` (repo root) and installs
`easy-opal==2.1.0` into it (pinned for reproducibility). The venv avoids the
`externally-managed-environment` error (PEP 668) seen on recent macOS / Ubuntu.

Activate it before running the following steps:

```bash
source .venv/bin/activate
easy-opal --version   # -> 2.1.0
easy-opal doctor      # checks Docker, permissions, etc.
```

### Alternative installers

`easy-opal` is a normal PyPI package, so any of these also work:

```bash
pipx install easy-opal==2.1.0      # isolated, on PATH globally
uv tool install easy-opal==2.1.0   # fastest
pip install easy-opal==2.1.0       # into the currently active environment
```
