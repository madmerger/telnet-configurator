#!/bin/sh
# Local SSH lab without root or Docker: a private sshd on 127.0.0.1 that serves
# each simulated device on its own port (22xx) via ForceCommand.
#   - public key auth only (a non-root sshd cannot check passwords; use lab/docker for that)
#   - login user is you ($USER)
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STATE="$ROOT/lab/.state"
CONF="$STATE/sshd_config"
"$ROOT/lab/keys.sh"

SSHD=$(command -v sshd 2>/dev/null || true)
[ -n "$SSHD" ] || for c in /usr/sbin/sshd /usr/local/sbin/sshd; do [ -x "$c" ] && SSHD=$c && break; done
[ -n "$SSHD" ] || { echo "sshd not found (Ubuntu: sudo apt install openssh-server)" >&2; exit 1; }
PERL=$(command -v perl)
USER_NAME=$(id -un)

if [ -f "$STATE/sshd.pid" ] && kill -0 "$(cat "$STATE/sshd.pid")" 2>/dev/null; then
    echo "lab/ssh: already running (pid $(cat "$STATE/sshd.pid"))"
    exit 0
fi

cp "$STATE/cbt_id_ed25519.pub" "$STATE/authorized_keys"
chmod 600 "$STATE/authorized_keys"

{
    echo "ListenAddress 127.0.0.1"
    awk '!/^[[:space:]]*(#|$)/ { print "Port " ($2 - 100) }' "$ROOT/sim/devices.conf"
    cat <<CFG
HostKey $STATE/ssh_host_ed25519_key
PidFile $STATE/sshd.pid
AuthorizedKeysFile $STATE/authorized_keys
AllowUsers $USER_NAME
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
StrictModes no
PermitTTY yes
X11Forwarding no
AllowTcpForwarding no
LogLevel INFO
CFG
    awk -v perl="$PERL" -v root="$ROOT" '!/^[[:space:]]*(#|$)/ {
        printf "Match LocalPort %d\n    ForceCommand \"%s\" \"%s/sim/bs-cli.pl\" --profile %s --hostname %s\n", $2 - 100, perl, root, $1, $3
    }' "$ROOT/sim/devices.conf"
} > "$CONF"

"$SSHD" -t -f "$CONF"
"$SSHD" -f "$CONF" -E "$STATE/sshd.log"
sleep 1
awk -v u="$USER_NAME" -v key="$STATE/cbt_id_ed25519" '!/^[[:space:]]*(#|$)/ {
    printf "lab/ssh: %-14s %-10s ssh -i %s -p %d %s@127.0.0.1\n", $3, $1, key, $2 - 100, u
}' "$ROOT/sim/devices.conf"
