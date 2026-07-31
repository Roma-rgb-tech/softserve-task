#!/bin/bash
# Builds and publishes every service image to the registry.
#
#   ./infra/scripts/publish-images.sh [tag]
#
# Run this on your own machine (not on a VM) after changing service code, then
# `vagrant provision` — the VMs pull the published image instead of compiling
# dependencies five times over.
#
# Requires `docker login` first.
set -euo pipefail

NAMESPACE="${REGISTRY_NAMESPACE:-tripletsrc}"
TAG="${1:-latest}"

# The VMs are arm64 (Apple Silicon host), so a plain build on the same machine
# already produces the right architecture. Set PLATFORM to override if you ever
# build somewhere else.
PLATFORM="${PLATFORM:-linux/arm64}"

SERVICES=(backend-service history-service fetcher-service ui-service)

cd "$(dirname "$0")/../.."   # repo root, so the build contexts resolve

for svc in "${SERVICES[@]}"; do
  image="$NAMESPACE/$svc:$TAG"
  echo ""
  echo "=== $image ==="
  docker build --platform "$PLATFORM" -t "$image" "./$svc"
  docker push "$image"
done

echo ""
echo "published tag '$TAG' for: ${SERVICES[*]}"
echo "now run: sudo -E vagrant provision"
