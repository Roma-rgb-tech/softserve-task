#!/bin/bash
# Creates one login per public key found in the uploaded keys directory.
#
# The filename is the username: infra/keys/roman.pub becomes the user `roman`
# with that key in ~/.ssh/authorized_keys. A file may hold several keys, one
# per line, if the same person logs in from more than one machine.
#
# Everything here is idempotent — re-running only adds what's missing, so a
# repeated `vagrant provision` never duplicates users or key lines.
set -euo pipefail

KEYS_DIR="${1:-/tmp/keys}"

if [ ! -d "$KEYS_DIR" ]; then
  echo "no keys directory at $KEYS_DIR — nothing to do"
  exit 0
fi

shopt -s nullglob
pubs=("$KEYS_DIR"/*.pub)

if [ ${#pubs[@]} -eq 0 ]; then
  echo "no *.pub files in $KEYS_DIR — nothing to do"
  exit 0
fi

for pub in "${pubs[@]}"; do
  user="$(basename "$pub" .pub)"

  # Guard against a stray filename turning into a broken account.
  if ! [[ "$user" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "skipping '$user': not a valid username"
    continue
  fi

  if ! id "$user" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$user"
    echo "created user $user"
  fi

  # Passwordless sudo, and docker access so they can inspect containers
  # without another privilege hop.
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$user" > "/etc/sudoers.d/90-$user"
  chmod 0440 "/etc/sudoers.d/90-$user"
  usermod -aG docker "$user" 2>/dev/null || true

  home="$(getent passwd "$user" | cut -d: -f6)"
  install -d -m 0700 -o "$user" -g "$user" "$home/.ssh"
  auth="$home/.ssh/authorized_keys"
  touch "$auth"

  # Append only the keys that aren't already there, so the file doesn't grow
  # on every provision.
  added=0
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "$key" in \#*) continue ;; esac
    if ! grep -qxF "$key" "$auth"; then
      printf '%s\n' "$key" >> "$auth"
      added=$((added + 1))
    fi
  done < "$pub"

  chown "$user:$user" "$auth"
  chmod 0600 "$auth"

  echo "$user: $added new key(s), $(wc -l < "$auth") total"
done

echo "authorized logins: $(ls "$KEYS_DIR"/*.pub | xargs -n1 basename | sed 's/\.pub$//' | tr '\n' ' ')"
