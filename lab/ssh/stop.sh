#!/bin/sh
set -eu
STATE="$(cd "$(dirname "$0")/.." && pwd)/.state"
if [ -f "$STATE/sshd.pid" ]; then
    kill "$(cat "$STATE/sshd.pid")" 2>/dev/null || true
    rm -f "$STATE/sshd.pid"
    echo "lab/ssh: stopped"
fi
