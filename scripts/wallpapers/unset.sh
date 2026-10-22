#!/usr/bin/env bash
# Outputs wallr has no wallpaper for (no last_wallpaper state file: a newly
# plugged monitor — wallr restores only the outputs it remembers).
# Usage: unset.sh <output>...
# Prints "=<path>" (the original wallpaper of the first given output that has
# one, via current.sh), then one line per output without a state file.
dir="$HOME/.cache/wallr/last_wallpaper"
src=""
for out in "$@"; do
    if [ -s "$dir/$out" ]; then
        [ -n "$src" ] || src=$("$(dirname "$0")/current.sh" "$out")
    else
        printf '%s\n' "$out"
    fi
done
[ -n "$src" ] && printf '=%s\n' "$src"
exit 0
