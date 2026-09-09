#!/usr/bin/env bash

set -euo pipefail

table="${1:-/etc/oilscope/disks}"
[ -r "$table" ] || exit 0

blank_device() {
  local want_bytes="$1" device size

  while read -r device size; do
    [ -n "$device" ] || continue
    [ "$size" = "$want_bytes" ] || continue
    [ -z "$(lsblk --noheadings --output NAME --paths "$device" | tail -n +2)" ] || continue
    [ -z "$(lsblk --noheadings --output FSTYPE "$device" | head -1 | tr -d '[:space:]')" ] || continue
    [ -z "$(lsblk --noheadings --output MOUNTPOINT "$device" | head -1 | tr -d '[:space:]')" ] || continue

    printf '%s\n' "$device"
    return 0
  done < <(lsblk --bytes --noheadings --nodeps --output PATH,SIZE)

  return 1
}

while read -r size_gb mount_path label _rest; do
  case "$size_gb" in '' | \#*) continue ;; esac

  findmnt --noheadings --mountpoint "$mount_path" >/dev/null 2>&1 && continue

  want_bytes=$((size_gb * 1024 * 1024 * 1024))

  if ! device="$(blank_device "$want_bytes")"; then
    echo "oilscope: no blank ${size_gb}G disk left for ${mount_path}" >&2
    continue
  fi

  mkfs.ext4 -q -L "$label" "$device"
  uuid="$(blkid --output value --match-tag UUID "$device")"

  mkdir -p "$mount_path"
  grep -q "UUID=${uuid}" /etc/fstab ||
    printf 'UUID=%s %s ext4 defaults,nofail 0 2\n' "$uuid" "$mount_path" >>/etc/fstab

  systemctl daemon-reload
  mount "$mount_path"
done <"$table"
