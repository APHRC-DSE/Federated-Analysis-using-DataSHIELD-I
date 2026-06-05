#!/usr/bin/env bash
# Build and push the rock-dsomop-dswb-reproducibility image to Docker Hub for linux/amd64.
#
# Prerequisites:
#   - docker login   (to the account that owns $IMAGE)
#   - Docker Desktop / buildx (QEMU is bundled, needed when building amd64 on Apple Silicon)
#
# Usage:
#   IMAGE=youruser/rock-dsomop-dswb-reproducibility ./build_and_push.sh
#   IMAGE=youruser/rock-dsomop-dswb-reproducibility TAG=2.0.0 DSOMOP_REF=2.0.0 ./build_and_push.sh
set -euo pipefail

IMAGE="${IMAGE:-}"
TAG="${TAG:-2.0.0}"
DSOMOP_REF="${DSOMOP_REF:-2.0.0}"   # tag 2.0.0 == commit a4dfe1a; override with a SHA to pin exactly
ROCK_BASE="${ROCK_BASE:-datashield/rock-base:6.3.5-R4.5.3}"

if [ -z "$IMAGE" ]; then
  echo "ERROR: set IMAGE to your Docker Hub repo, e.g. IMAGE=youruser/rock-dsomop-dswb-reproducibility" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# A docker-container builder is required to --push from buildx.
docker buildx create --name rockbuilder --use >/dev/null 2>&1 || docker buildx use rockbuilder

echo "==> Building ${IMAGE}:${TAG} (linux/amd64, dsOMOP ref=${DSOMOP_REF})"
docker buildx build \
  --platform linux/amd64 \
  --build-arg ROCK_BASE="$ROCK_BASE" \
  --build-arg DSOMOP_REF="$DSOMOP_REF" \
  -t "${IMAGE}:${TAG}" \
  -t "${IMAGE}:latest" \
  --push \
  "$SCRIPT_DIR"

echo "==> Pushed ${IMAGE}:${TAG} and ${IMAGE}:latest"
