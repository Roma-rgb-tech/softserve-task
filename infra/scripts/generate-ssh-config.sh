#!/bin/bash
# Generates ~/.ssh/my_project_config with Host entries for the project VMs,
# and wires it into ~/.ssh/config via Include so `ssh <alias>` just works.
#
# Re-running overwrites the file from scratch (see `: > "$OUT"` below), so
# repeated runs never duplicate or accumulate stale Host blocks.
set -euo pipefail

OUT="$HOME/.ssh/my_project_config"
SSH_CONFIG="$HOME/.ssh/config"

DEFAULT_USER="roman"
IDENTITY_FILE="$HOME/.ssh/id_ed25519"

add_host() {
    local alias="$1"
    local ip="$2"

    cat >> "$OUT" <<EOF
Host $alias
    HostName $ip
    User $DEFAULT_USER
    IdentityFile $IDENTITY_FILE
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

EOF
}

: > "$OUT"
add_host postgres 192.168.88.200
add_host history  192.168.88.201
add_host backend  192.168.88.202
add_host fetcher  192.168.88.203
add_host ui       192.168.88.204
chmod 600 "$OUT"

# Wire the generated file into the real ssh config, once.
mkdir -p "$(dirname "$SSH_CONFIG")"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if ! grep -qxF "Include $OUT" "$SSH_CONFIG"; then
    # Include must be the first line ssh sees for later Host blocks in
    # $SSH_CONFIG not to shadow these entries, so prepend rather than append.
    tmp="$(mktemp)"
    { echo "Include $OUT"; echo; cat "$SSH_CONFIG"; } > "$tmp"
    mv "$tmp" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    echo "added 'Include $OUT' to $SSH_CONFIG"
else
    echo "$SSH_CONFIG already includes $OUT"
fi

echo "wrote $(grep -c '^Host ' "$OUT") host(s) to $OUT"
