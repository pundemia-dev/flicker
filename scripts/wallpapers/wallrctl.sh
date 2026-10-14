#!/usr/bin/env bash
# wallr playback control per output (services/WallrClock). wallr 0.6.4 quirks:
# - a VIDEO paused > 5 s is dead after `resume` (its stall watchdog), and a
#   `set` of the same path + effect is a no-op → revive = two instant sets
#   with different effects;
# - `seek` while paused corrupts its pause bookkeeping (resume can panic) →
#   always resume (or revive) FIRST, then seek;
# - the position is only in `wallr ipc info` text: "State: playing @ 71.62s".
# Usage:
#   wallrctl.sh pos <out>                     → seconds (empty if no video)
#   wallrctl.sh pause <out>                   → pause, then print the frozen position
#   wallrctl.sh resume <out> <seek|-|here> <0|1> → resume (1 = revive a video), then seek
#                                               (here = the position before resuming)
#   wallrctl.sh seek <out> <seconds>          → seek a PLAYING video
#   wallrctl.sh resync <out> <lead s>         → revive a video in place at its own clock
#                                               (+ the time the revive took + lead)
set -u
cmd=$1 out=$2

pos() {
    wallr ipc info -m "$out" 2>/dev/null | sed -n 's/.*State: [a-z]* @ \([0-9.]*\)s.*/\1/p' | head -1
}

case "$cmd" in
pos)
    pos
    ;;
seek)
    wallr ipc seek "$3" -m "$out" >/dev/null 2>&1
    ;;
resync)
    t0=$(date +%s%N)
    p=$(pos)
    w=$(cat "$HOME/.cache/wallr/last_wallpaper/$out" 2>/dev/null)
    case "${w,,}" in *.mp4 | *.webm | *.mkv | *.mov | *.avi | *.m4v) ;; *) exit 0 ;; esac
    wallr set "$w" -m "$out" -e wipe -d 0ms --no-theme >/dev/null 2>&1
    wallr set "$w" -m "$out" -e fade -d 0ms --no-theme >/dev/null 2>&1
    [ -n "$p" ] || exit 0
    el=$(( ($(date +%s%N) - t0) / 1000000 ))
    wallr ipc seek "$(awk -v p="$p" -v e="$el" -v l="${3:-0.02}" 'BEGIN { printf "%.3f", p + e / 1000 + l }')" -m "$out" >/dev/null 2>&1
    ;;
pause)
    wallr ipc pause -m "$out" >/dev/null 2>&1
    pos
    ;;
resume)
    target=${3:--} revive=${4:-0}
    [ "$target" = here ] && target=$(pos) && [ -z "$target" ] && target=-
    p=$(cat "$HOME/.cache/wallr/last_wallpaper/$out" 2>/dev/null)
    video=0
    case "${p,,}" in *.mp4 | *.webm | *.mkv | *.mov | *.avi | *.m4v) video=1 ;; esac
    if [ "$revive" = 1 ] && [ "$video" = 1 ]; then
        wallr set "$p" -m "$out" -e wipe -d 0ms --no-theme >/dev/null 2>&1
        wallr set "$p" -m "$out" -e fade -d 0ms --no-theme >/dev/null 2>&1
    else
        wallr ipc resume -m "$out" >/dev/null 2>&1
    fi
    if [ "$video" = 1 ] && [ "$target" != "-" ]; then
        wallr ipc seek "$target" -m "$out" >/dev/null 2>&1
    fi
    ;;
esac
