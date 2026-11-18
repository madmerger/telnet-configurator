#!/bin/sh
# Telnet vs SSH, side by side: collects the same lab devices over Telnet (left,
# conf/devices.local.conf) and SSH (right, an SSH lab inventory) at the same time
# in two tmux panes, then diffs the results without the timestamp header line.
#
#   scripts/demo_telnet_vs_ssh.sh                 # run in tmux and attach
#   scripts/demo_telnet_vs_ssh.sh --mp4 demo.mp4  # record: Xvfb + xterm + ffmpeg (also writes demo.cast)
#     Ubuntu: sudo apt install tmux xvfb xterm x11-utils ffmpeg asciinema fonts-dejavu-core
#   scripts/demo_telnet_vs_ssh.sh --cast demo.cast  # record an asciinema cast only (needs a terminal)
#
# SSH side: lab/ssh (key auth, conf/devices.local-ssh.conf) by default;
# SSH_INVENTORY=conf/devices.local-docker.conf for lab/docker (password + key).
# Starts the Telnet simulator and lab/ssh if they are not running. Output: output/demo/{telnet,ssh}.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SELF="$ROOT/scripts/demo_telnet_vs_ssh.sh"
cd "$ROOT"
SESSION=cbt-demo
COLS=${DEMO_COLS:-200}
ROWS=${DEMO_ROWS:-52}
TELNET_INV=${TELNET_INVENTORY:-conf/devices.local.conf}
SSH_INV=${SSH_INVENTORY:-conf/devices.local-ssh.conf}
DEVICES="TKY-ENB-0001 OSK-ENB-0102 NGY-GNB-0203"
PAUSE=${DEMO_PAUSE:-2}
export CBT_PASSWORD=${CBT_PASSWORD:-cbt-pass} CBT_ENABLE_PASSWORD=${CBT_ENABLE_PASSWORD:-cbt-enable}

bold() { printf '\033[1;%sm%s\033[0m\n' "$1" "$2"; }
typed() {    # show a command as if typed, then run it
    printf '\033[1;32m$\033[0m %s\n' "$*"
    "$@"
}

# One side of the demo: collect device by device over the given inventory.
pane() {
    side=$1 inv=$2 color=$3
    clear
    bold "$color" "=== $(echo "$side" | tr a-z A-Z): bin/cbt-collect -i $inv ==="
    echo
    sleep "$PAUSE"
    for d in $DEVICES; do
        typed perl bin/cbt-collect -v -i "$inv" -d "$d" -o "output/demo/$side" --logdir "log/demo/$side" | grep -v 'devices collected$' | sed '/^$/d' || true
        echo
        sleep "$PAUSE"
    done
    bold "$color" "$side: collected $(ls output/demo/"$side"/*/latest.cfg | wc -l) of 3 devices"
    tmux wait-for -S "$SESSION-$side"
    sleep 600
}

compare() {
    clear
    bold 33 "=== diff telnet vs ssh (without the '!! CBT collected ... at <time>' header) ==="
    rc=0
    for d in $DEVICES; do
        t="output/demo/telnet/$d/latest.cfg" s="output/demo/ssh/$d/latest.cfg"
        printf '\033[1;32m$\033[0m diff <(grep -v "^!! CBT collected" %s) <(grep -v "^!! CBT collected" %s)\n' "$t" "$s"
        grep -v '^!! CBT collected' "$t" > "output/demo/$d.telnet"
        grep -v '^!! CBT collected' "$s" > "output/demo/$d.ssh"
        if diff "output/demo/$d.telnet" "output/demo/$d.ssh"; then
            printf '  \033[1;32m%s: identical (%s lines)\033[0m\n' "$d" "$(wc -l < "output/demo/$d.ssh")"
        else
            printf '  \033[1;31m%s: DIFFERENT\033[0m\n' "$d"; rc=1
        fi
        rm -f "output/demo/$d.telnet" "output/demo/$d.ssh"
        sleep 1
    done
    echo
    [ $rc = 0 ] && bold 32 "Telnet and SSH collected identical configurations." || bold 31 "Telnet and SSH differ."
    sleep "$PAUSE"; sleep "$PAUSE"
    tmux wait-for -S "$SESSION-done"
    sleep 600
}

case "${1:-}" in
    --pane) shift; pane "$@"; exit 0 ;;
    --compare) compare; exit 0 ;;
esac

# Driver: prepare labs, build the tmux layout, wait for both sides, then compare.
setup() {
    [ -f .run/sim.pid ] && kill -0 "$(cat .run/sim.pid)" 2>/dev/null || make -s sim-start >/dev/null
    case "$SSH_INV" in *local-ssh*) make -s lab-ssh-start >/dev/null ;; esac
    rm -rf output/demo log/demo
    mkdir -p output/demo log/demo
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS" "sleep 3600"
    tmux set -t "$SESSION" status off
    tmux set -t "$SESSION" pane-border-status top
    tmux set -t "$SESSION" pane-border-format ' #{pane_title} '
    tmux split-window -h -t "$SESSION:0.0" "sleep 3600"
    tmux select-pane -t "$SESSION:0.0" -T "Telnet  $TELNET_INV"
    tmux select-pane -t "$SESSION:0.1" -T "SSH  $SSH_INV"
}

play() {
    sleep 1
    tmux respawn-pane -k -t "$SESSION:0.0" "sh '$SELF' --pane telnet '$TELNET_INV' 36"
    tmux respawn-pane -k -t "$SESSION:0.1" "sh '$SELF' --pane ssh '$SSH_INV' 35"
    tmux wait-for "$SESSION-telnet"
    tmux wait-for "$SESSION-ssh"
    sleep 1
    tmux split-window -v -f -l 12 -t "$SESSION:0" "sh '$SELF' --compare"
    tmux select-pane -t "$SESSION:0.2" -T "diff"
    tmux wait-for "$SESSION-done"
    sleep "${DEMO_HOLD:-4}"          # keep the final diff on screen
    [ "${1:-}" = keep ] || tmux kill-session -t "$SESSION"
}

case "${1:-}" in
    --mp4)
        MP4=$2 CAST=${2%.mp4}.cast
        for c in Xvfb xterm xwininfo ffmpeg asciinema tmux; do command -v $c >/dev/null || { echo "$c not found" >&2; exit 1; }; done
        setup
        DISP=:${DEMO_DISPLAY:-87}
        Xvfb "$DISP" -screen 0 1920x1080x24 -nolisten tcp >/dev/null 2>&1 &
        XPID=$!
        sleep 1
        rm -f "$CAST"
        DISPLAY=$DISP xterm -T cbt-demo -geometry "${COLS}x${ROWS}+0+0" -fa 'DejaVu Sans Mono' -fs 11 -bg black -fg '#d0d0d0' \
            -e asciinema rec -q --overwrite -c "tmux attach -t $SESSION" "$CAST" &
        TPID=$!
        sleep 1.5
        # record just the xterm window (even width/height for H.264)
        W=$(xwininfo -display "$DISP" -name cbt-demo | awk '/Width:/ { print int($2 / 2) * 2 }')
        H=$(xwininfo -display "$DISP" -name cbt-demo | awk '/Height:/ { print int($2 / 2) * 2 }')
        ffmpeg -loglevel error -y -f x11grab -draw_mouse 0 -framerate 15 -video_size "${W}x${H}" -i "$DISP+0,0" \
            -c:v libx264 -pix_fmt yuv420p -preset veryfast "$MP4" &
        FPID=$!
        play keep
        kill -INT $FPID; wait $FPID || true
        tmux kill-session -t "$SESSION" 2>/dev/null || true
        kill $TPID 2>/dev/null || true; kill $XPID 2>/dev/null || true
        echo "wrote $MP4 and $CAST"
        ;;
    --cast)
        setup
        play &
        asciinema rec -q --overwrite -c "tmux attach -t $SESSION" "$2"
        wait
        ;;
    *)
        setup
        play &
        tmux attach -t "$SESSION"
        wait
        ;;
esac
