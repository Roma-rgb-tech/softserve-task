#!/bin/bash
set -euo pipefail

SERVICE_DIR="${1:?usage: deploy.sh <service-dir>}"
cd "$SERVICE_DIR"

if [ ! -f .env ]; then
  echo "no .env in $SERVICE_DIR — the provisioner should have written one" >&2
  exit 1
fi


for legacy in postgres redis rabbitmq history backend fetcher ui; do
  docker rm -f "$legacy" 2>/dev/null || true
done

docker compose up -d --build --remove-orphans
docker compose ps
