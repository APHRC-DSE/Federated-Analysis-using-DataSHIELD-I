#!/usr/bin/env bash
# Step 2 — Stand up the three federated Opal + Rock sites with easy-opal.
#
# Creates three independent easy-opal instances — aphrc, dgh, iressef — each:
#   - Opal + MongoDB, served over plain HTTP on a fixed localhost port
#     (48080 / 48081 / 48082). SSL is intentionally off: everything is on
#     localhost, so plain HTTP keeps the client reproducible (no certs).
#   - the upstream default Rock profile ("rock") left in place, plus our dsOMOP
#     image added as a second profile named "omop" — the one the DataSHIELD
#     client logs into (profile = "omop").
#   - the Opal admin password forced to "password" (intentional, public demo).
#
# Ports and credentials are HARDCODED below — no sites.env, no auto-probing. If
# one of the ports is already taken on your machine, edit OPAL_PORTS and re-run.
# The later steps (3, 4, 5) and the book use the SAME fixed values, so if you
# change a port here, change it there too.
#
# Prerequisites:
#   - Step 1 done: easy-opal installed in ../.venv (or otherwise on PATH).
#   - Docker running.
#   - The dsOMOP Rock image. IMAGE defaults to the published, public
#     davidsarrat/rock-dsomop-dswb-reproducibility; override it to use your own
#     (built & pushed from docker/rock-dsomop-dswb-reproducibility/).
#
# Usage:
#   bash 2_opal_stacks/setup_sites.sh                                              # published image
#   IMAGE=youruser/rock-dsomop-dswb-reproducibility bash 2_opal_stacks/setup_sites.sh   # your own
set -euo pipefail

# --- fixed configuration (edit if a port is taken) -------------------------
SITES=(aphrc dgh iressef)
OPAL_PORTS=(48080 48081 48082)           # one localhost HTTP port per site, same order as SITES

IMAGE="${IMAGE:-davidsarrat/rock-dsomop-dswb-reproducibility}"   # published image; override to use your own
TAG="${TAG:-2.0.0}"
PROFILE_NAME="omop"                      # Rock profile the client logs into (profile = this)
ADMIN_PASSWORD="password"                # intentional, public demo password
OPAL_VERSION="${OPAL_VERSION:-5.5.1}"    # pinned for reproducibility; override via env to upgrade
MONGO_VERSION="${MONGO_VERSION:-8.2.4}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EO_HOME="${EASY_OPAL_HOME:-$HOME/.easy-opal}"

# The dsOMOP image is published for linux/amd64 only. On an arm64 host (Apple
# Silicon) a plain pull asks for a linux/arm64 manifest that does not exist, so
# we force linux/amd64 for the profile-add pull (the image then runs emulated).
# Scoped to the pull ONLY — not setup/restart — so the multi-arch mongo/opal
# images keep running natively. Empty on amd64 hosts (Docker ignores it).
PULL_PLATFORM=""
case "$(uname -m)" in
  arm64 | aarch64) PULL_PLATFORM="linux/amd64" ;;
esac

# --- preconditions ---------------------------------------------------------
if [ -f "$REPO_ROOT/.venv/bin/activate" ]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.venv/bin/activate"
fi
if ! command -v easy-opal >/dev/null 2>&1; then
  echo "ERROR: easy-opal not found. Run step 1 first: bash 1_setup/install_easy_opal.sh" >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running. Start Docker and retry." >&2
  exit 1
fi

# --- pre-flight: the fixed ports must be free ------------------------------
# /dev/tcp connect succeeds => something is listening => port is in use.
port_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
for i in "${!SITES[@]}"; do
  if ! port_free "${OPAL_PORTS[$i]}"; then
    echo "ERROR: port ${OPAL_PORTS[$i]} (for site '${SITES[$i]}') is already in use." >&2
    echo "       Edit OPAL_PORTS at the top of this script (and match it in steps 3-5" >&2
    echo "       and the book) to a free port, then re-run." >&2
    exit 1
  fi
done

echo "==> Opal sites: ${SITES[*]} on http://localhost:{${OPAL_PORTS[*]}}"

# --- bring up each site ----------------------------------------------------
for i in "${!SITES[@]}"; do
  site="${SITES[$i]}"
  port="${OPAL_PORTS[$i]}"
  echo "==> [${site}] setup on http://localhost:${port}"

  [ -d "$EO_HOME/instances/$site" ] || easy-opal instance create "$site"

  easy-opal -i "$site" setup \
    --stack-name "$site" --ssl-strategy none --host localhost \
    --http-port "$port" --password "$ADMIN_PASSWORD" \
    --opal-version "$OPAL_VERSION" --mongo-version "$MONGO_VERSION" --yes

  echo "==> [${site}] add dsOMOP profile '${PROFILE_NAME}' (${IMAGE}:${TAG})"
  DOCKER_DEFAULT_PLATFORM="$PULL_PLATFORM" \
    easy-opal -i "$site" profile add --image "$IMAGE" --tag "$TAG" --name "$PROFILE_NAME" --yes
  # 'profile add' exits 0 even when the image pull fails (the profile is just
  # skipped), so confirm it was actually registered before moving on.
  if ! easy-opal -i "$site" profile list 2>/dev/null | grep -qw "$PROFILE_NAME"; then
    echo "ERROR: profile '$PROFILE_NAME' was not added on '$site' — the '${IMAGE}:${TAG}' pull failed." >&2
    echo "       On Apple Silicon, confirm the image is pullable for linux/amd64." >&2
    exit 1
  fi
  easy-opal -i "$site" restart
done

echo
echo "==> All sites up:"
for i in "${!SITES[@]}"; do
  printf '    %-8s http://localhost:%s\n' "${SITES[$i]}" "${OPAL_PORTS[$i]}"
done
echo
echo "Login: administrator / ${ADMIN_PASSWORD}   (profile: ${PROFILE_NAME})"
echo "Next: seed the OMOP databases (step 3), then create resources (step 4)."
