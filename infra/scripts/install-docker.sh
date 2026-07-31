#!/usr/bin/env bash
# Installs Docker Engine and the Compose v2 plugin on a fresh VM.
#
# Ubuntu's own docker.io package ships without the compose plugin, and jammy
# has no docker-compose-v2 package, so we add Docker's own repository instead
# of stitching together a v1 fallback.
set -euo pipefail

if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
  echo "docker + compose already present, skipping"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable --now docker

# So `docker ps` works over plain `vagrant ssh` without sudo. Takes effect on
# the next login, which is fine — provisioning itself runs as root.
usermod -aG docker vagrant

docker --version
docker compose version
