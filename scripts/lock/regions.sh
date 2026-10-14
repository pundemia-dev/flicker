#!/usr/bin/env bash
# Lock-screen dissolve input for one output: the wallpaper wallr shows there
# (the fill-blur composite itself when setwall.sh made one — that is what is on
# screen) + the grab regions that differ from it (diff.py).
# Usage: regions.sh <grab.ppm|-> <output> [diff.py options...]  (- = no grab:
# only the wallpaper, no regions)
# Prints one JSON line: diff.py's object + "wallpaper" (path, "" = none) +
# "kind" (image | animated | video). A moving wallpaper (GIF / video) can't be
# compared with a grab — diff.py only inpaints (--no-diff) and the lock takes
# the regions from the compositor's window geometry instead.
set -u
grab=$1 out=$2
shift 2
dir=$(dirname "$(readlink -f "$0")")
wall=$(cat "$HOME/.cache/wallr/last_wallpaper/$out" 2>/dev/null)
kind=image
case "${wall,,}" in
*.gif) kind=animated ;;
*.mp4 | *.webm | *.mkv | *.mov | *.avi | *.m4v) kind=video ;;
esac
[ -n "$wall" ] && [ ! -r "$wall" ] && wall=""
if [ "$grab" = "-" ]; then
    json='{"w": 0, "h": 0, "coverage": 0, "whole": false, "regions": []}'
elif [ -z "$wall" ]; then
    json=$(python3 "$dir/diff.py" "$grab" /nonexistent "$@" 2>/dev/null)
elif [ "$kind" != image ]; then
    json=$(python3 "$dir/diff.py" "$grab" /nonexistent --no-diff "$@")
else
    json=$(python3 "$dir/diff.py" "$grab" "$wall" "$@")
fi
[ -n "$json" ] || exit 1
w=${wall//\\/\\\\}
w=${w//\"/\\\"}
printf '%s, "wallpaper": "%s", "kind": "%s"}\n' "${json%\}}" "$w" "$kind"
