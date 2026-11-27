#!/bin/sh
# Creates the lab's SSH client key (lab/.state/cbt_id_ed25519) used by the collector, the host keys
# of lab/ssh and lab/docker, and lab/.state/known_hosts registering those host keys for their ports.
set -eu
LAB=$(cd "$(dirname "$0")" && pwd)
STATE="$LAB/.state"
mkdir -p "$STATE"
chmod 700 "$STATE"
if [ ! -f "$STATE/cbt_id_ed25519" ]; then
    ssh-keygen -q -t ed25519 -N '' -C cbt-collector-lab -f "$STATE/cbt_id_ed25519"
    echo "lab: created client key $STATE/cbt_id_ed25519"
fi
for k in ssh_host_ed25519_key docker_host_ed25519_key; do
    [ -f "$STATE/$k" ] || ssh-keygen -q -t ed25519 -N '' -C cbt-lab-host -f "$STATE/$k"
done
hosts() { awk -v d="$1" '!/^[[:space:]]*(#|$)/ { printf "%s[127.0.0.1]:%d", (n++ ? "," : ""), $2 + d }' "$LAB/../sim/devices.conf"; }
{
    echo "$(hosts -100) $(cut -d' ' -f1,2 "$STATE/ssh_host_ed25519_key.pub")"
    echo "$(hosts 100) $(cut -d' ' -f1,2 "$STATE/docker_host_ed25519_key.pub")"
} > "$STATE/known_hosts"
