#!/bin/bash
# Brings up one VM's compose stack.
#
#   deploy.sh <service-dir>
#
# The directory holds a docker-compose.yml plus a .env written by the Vagrant
# provisioner. Running from inside it means Compose picks that .env up on its
# own and uses the directory name as the project name.
#
# Images come from the registry — nothing is built here. Publish them from the
# host first with infra/scripts/publish-images.sh.
set -euo pipefail

SERVICE_DIR="${1:?usage: deploy.sh <service-dir>}"
cd "$SERVICE_DIR"

if [ ! -f .env ]; then
  echo "no .env in $SERVICE_DIR — the provisioner should have written one" >&2
  exit 1
fi

# Always fetch the newest image for the configured tag. Without this a VM that
# already has :latest cached would keep running yesterday's build.
docker compose pull

docker compose up -d --remove-orphans
docker compose ps
