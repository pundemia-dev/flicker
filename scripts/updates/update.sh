#!/usr/bin/env bash
# System update runner for services/Updates.qml (island module `updates`).
# The transaction runs in its own tmux server (`-L flicker`, session
# `update`), NOT as a child of the shell: Quickshell kills its children on
# every reload, and a pacman killed mid-transaction can leave the system
# broken. tmux also gives pacman / yay a real tty (prompts, PKGBUILD menus)
# that the user can attach to (`attach`), while `script` copies the pane's
# output to the log the island reads. The tmux server gets its own systemd
# scope: the shell runs inside the compositor's unit (driftwm.service,
# KillMode=control-group), so a compositor crash / restart would otherwise
# take the transaction down with it.
# Root comes from pkexec (the island's polkit agent asks), no sudo:
#   repo  pkexec pacman -Syu          (official repositories only)
#   all   yay -Syu --sudo pkexec       (repositories first, then the AUR)
#
#   list               pending updates, one per line:
#                      "repo|aur <name> <old> <new>"; "error repo" when
#                      checkupdates failed (no network / mirrors)
#   start repo|all     start a run (exit 2 = one is already running)
#   poll               "status: <line or empty>", "alive: 0|1", "size: <log
#                      bytes>", "mode: <repo|all>", "---", then
#                      the last LOG_TAIL bytes of the log
#   send <keys>        type <keys> + Enter into the run's tty
#   attach             attach the terminal this is run in (kitty -e …)
#   clear              forget a finished run (log + status)
#
# Status line (written when the command exits):
#   "exit=<code> reboot=0|1 pacnew=<n> mode=<repo|all>"
# reboot = the running kernel's modules are gone (the kernel was upgraded).

set -u
SOCK=flicker
SESSION=update
DIR="${XDG_RUNTIME_DIR:-/tmp}/flicker/update"
LOG="$DIR/log"
STATUS="$DIR/status"
LOG_TAIL=${LOG_TAIL:-16000}

tm() { tmux -L "$SOCK" "$@"; }
alive() { tm has-session -t "$SESSION" 2>/dev/null; }

case "${1:-}" in
list)
    # checkupdates: 0 = updates, 2 = none, anything else = it failed.
    repo=$(checkupdates 2>/dev/null)
    rc=$?
    [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || echo "error repo"
    printf '%s\n' "$repo" | awk 'NF >= 4 { print "repo", $1, $2, $4 }'
    yay -Qua 2>/dev/null | awk 'NF >= 4 { print "aur", $1, $2, $4 }'
    true
    ;;
start)
    mode=${2:-repo}
    [ "$mode" = repo ] || [ "$mode" = all ] || { echo "mode: repo|all" >&2; exit 1; }
    if alive && [ ! -e "$STATUS" ]; then
        exit 2
    fi
    tm kill-session -t "$SESSION" 2>/dev/null
    mkdir -p "$DIR"
    rm -f "$LOG" "$STATUS"
    : > "$LOG"
    echo "$mode" > "$DIR/mode"
    scope=()
    command -v systemd-run >/dev/null && scope=(systemd-run --user --scope --quiet --collect)
    "${scope[@]}" tmux -L "$SOCK" new-session -d -s "$SESSION" -x 160 -y 48 bash "$0" _run "$mode"
    ;;
_run)
    mode=$2
    if [ "$mode" = all ]; then
        cmd="yay -Syu --sudo pkexec"
    else
        cmd="pkexec pacman -Syu"
    fi
    # -e: the child's exit code; -f: flush on every write (the island tails it).
    # script runs the command through $SHELL (fish here): pin bash.
    SHELL=/bin/bash script -qfec "$cmd" "$LOG"
    code=$?
    reboot=0
    [ -d "/usr/lib/modules/$(uname -r)" ] || reboot=1
    pacnew=$(grep -c '\.pacnew' "$LOG" 2>/dev/null)
    echo "exit=$code reboot=$reboot pacnew=${pacnew:-0} mode=$mode" > "$STATUS"
    # Someone is watching in a terminal: keep the pane until they read it.
    if [ -n "$(tm list-clients -t "$SESSION" 2>/dev/null)" ]; then
        echo
        echo "[exit $code] Press Enter to close"
        read -r _
    fi
    ;;
poll)
    echo "status: $(cat "$STATUS" 2>/dev/null)"
    if alive; then echo "alive: 1"; else echo "alive: 0"; fi
    echo "size: $(stat -c %s "$LOG" 2>/dev/null || echo 0)"
    echo "mode: $(cat "$DIR/mode" 2>/dev/null)"
    echo "---"
    tail -c "$LOG_TAIL" "$LOG" 2>/dev/null
    true
    ;;
send)
    alive || exit 1
    [ -n "${2:-}" ] && tm send-keys -t "$SESSION" -l -- "$2"
    tm send-keys -t "$SESSION" Enter
    ;;
attach)
    exec tmux -L "$SOCK" attach -t "$SESSION"
    ;;
clear)
    alive && [ ! -e "$STATUS" ] && exit 2
    tm kill-session -t "$SESSION" 2>/dev/null
    rm -f "$LOG" "$STATUS" "$DIR/mode"
    true
    ;;
*)
    sed -n '2,25p' "$0" >&2
    exit 1
    ;;
esac
