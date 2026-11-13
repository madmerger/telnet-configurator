#!/bin/sh
# Creates the lab's SSH client key (lab/.state/cbt_id_ed25519) used by the collector.
set -eu
LAB=$(cd "$(dirname "$0")" && pwd)
STATE="$LAB/.state"
mkdir -p "$STATE"
chmod 700 "$STATE"
if [ ! -f "$STATE/cbt_id_ed25519" ]; then
    ssh-keygen -q -t ed25519 -N '' -C cbt-collector-lab -f "$STATE/cbt_id_ed25519"
    echo "lab: created client key $STATE/cbt_id_ed25519"
fi
