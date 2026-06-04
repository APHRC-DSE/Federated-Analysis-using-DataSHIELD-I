#!/usr/bin/env bash
# Step 1 of the reproducibility package for "Federated Analysis using DataSHIELD".
# Installs easy-opal (pinned) into a local virtual environment at the repo root.
set -euo pipefail

EASY_OPAL_VERSION="2.1.0"
MIN_PY_MAJOR=3
MIN_PY_MINOR=11

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV_DIR="$REPO_ROOT/.venv"

echo "==> Checking prerequisites"

# --- Python >= 3.11 (required by easy-opal) ---
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found. Install Python >= ${MIN_PY_MAJOR}.${MIN_PY_MINOR} and retry." >&2
  exit 1
fi
if ! python3 -c "import sys; raise SystemExit(0 if sys.version_info >= (${MIN_PY_MAJOR}, ${MIN_PY_MINOR}) else 1)"; then
  echo "ERROR: easy-opal ${EASY_OPAL_VERSION} requires Python >= ${MIN_PY_MAJOR}.${MIN_PY_MINOR}." >&2
  echo "       Found: $(python3 --version 2>&1)" >&2
  exit 1
fi
echo "    Python OK: $(python3 --version 2>&1)"

# --- Docker (needed for steps 2+, not for this install) ---
if command -v docker >/dev/null 2>&1; then
  echo "    Docker OK: $(docker --version 2>&1)"
  if ! docker compose version >/dev/null 2>&1; then
    echo "    WARNING: 'docker compose' (Compose v2) not detected. Needed for steps 2+."
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "    WARNING: Docker daemon not reachable. Start Docker before step 2."
  fi
else
  echo "    WARNING: Docker not found. Required for steps 2+ (Opal / Rock / PostgreSQL)."
fi

# --- Virtual environment + install ---
echo "==> Creating virtual environment at $VENV_DIR"
if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR"
fi
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

echo "==> Installing easy-opal==${EASY_OPAL_VERSION}"
python -m pip install --upgrade pip >/dev/null
python -m pip install "easy-opal==${EASY_OPAL_VERSION}"

echo "==> Installed:"
easy-opal --version || true

cat <<EOF

Done. easy-opal ${EASY_OPAL_VERSION} is installed in:
    $VENV_DIR

Activate it before running the following steps:
    source "$VENV_DIR/bin/activate"

Then verify:
    easy-opal --version
    easy-opal doctor
EOF
