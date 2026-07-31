#!/usr/bin/env bash
set -euo pipefail

SERVICE_DIR="${1:?usage: deploy.sh <service-dir>}"
cd "$SERVICE_DIR"

if [ ! -f .env ]; then
  echo "no .env in $SERVICE_DIR — the provisioner should have written one" >&2
  exit 1
fi

# Containers from the earlier `docker run` layout hold the same published
# ports and would block the stack from starting. Harmless once they're gone.
for legacy in postgres redis rabbitmq history backend fetcher ui; do
  docker rm -f "$legacy" 2>/dev/null || true
done

docker compose up -d --build --remove-orphans
docker compose ps
