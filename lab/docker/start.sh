#!/bin/sh
# SSH lab in Docker: the simulated devices on 127.0.0.1:2401-2403,
# user cbtadmin, password cbt-pass, or the lab key lab/.state/cbt_id_ed25519.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
"$ROOT/lab/keys.sh"
docker build -q -t cbt-bs-sim-ssh -f "$ROOT/lab/docker/Dockerfile" "$ROOT" >/dev/null
docker rm -f cbt-bs-sim-ssh >/dev/null 2>&1 || true
PORTS=$(awk '!/^[[:space:]]*(#|$)/ { printf "-p 127.0.0.1:%d:%d ", $2 + 100, $2 + 100 }' "$ROOT/sim/devices.conf")
# shellcheck disable=SC2086
docker run -d --name cbt-bs-sim-ssh $PORTS -v "$ROOT/lab/.state:/keys:ro" cbt-bs-sim-ssh >/dev/null
awk '!/^[[:space:]]*(#|$)/ {
    printf "lab/docker: %-14s %-10s ssh -p %d cbtadmin@127.0.0.1   (password: cbt-pass)\n", $3, $1, $2 + 100
}' "$ROOT/sim/devices.conf"
