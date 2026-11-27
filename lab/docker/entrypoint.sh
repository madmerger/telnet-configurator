#!/bin/sh
# Serves every device from /opt/sim/devices.conf on port 24xx (telnet port + 100).
set -eu
KEYS=${KEYS:-/keys}
ssh-keygen -A >/dev/null
HOSTKEY=
if [ -f "$KEYS/docker_host_ed25519_key" ]; then    # registered in lab/.state/known_hosts by lab/keys.sh
    HOSTKEY=/etc/ssh/ssh_host_lab_ed25519_key
    install -m 600 "$KEYS/docker_host_ed25519_key" "$HOSTKEY"
fi
mkdir -p /home/cbtadmin/.ssh
if [ -f "$KEYS/cbt_id_ed25519.pub" ]; then
    cp "$KEYS/cbt_id_ed25519.pub" /home/cbtadmin/.ssh/authorized_keys
fi
chown -R cbtadmin /home/cbtadmin/.ssh
chmod 700 /home/cbtadmin/.ssh
chmod 600 /home/cbtadmin/.ssh/authorized_keys 2>/dev/null || true

CONF=/etc/ssh/sshd_config.lab
{
    awk '!/^[[:space:]]*(#|$)/ { print "Port " ($2 + 100) }' /opt/sim/devices.conf
    [ -z "$HOSTKEY" ] || echo "HostKey $HOSTKEY"
    cat <<CFG
AllowUsers cbtadmin
PubkeyAuthentication yes
PasswordAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
PermitRootLogin no
X11Forwarding no
AllowTcpForwarding no
CFG
    awk '!/^[[:space:]]*(#|$)/ {
        printf "Match LocalPort %d\n    ForceCommand /usr/bin/perl /opt/sim/bs-cli.pl --profile %s --hostname %s\n", $2 + 100, $1, $3
    }' /opt/sim/devices.conf
} > "$CONF"
exec /usr/sbin/sshd -D -e -f "$CONF"
