#!/usr/bin/env bash
# Lock-screen dissolve input for one output: the wallpaper wallr shows there
# (the fill-blur composite itself when setwall.sh made one — that is what is on
# screen) + the grab regions that differ from it (diff.py).
# Usage: regions.sh <grab.ppm|-> <output> [diff.py options...]  (- = no grab:
# only the wallpaper, no regions)
# Prints one JSON line: diff.py's object + "wallpaper" (path, "" = none) +
# "kind" (image | animated | video; a moving one only when no frame could be
# extracted — diff.py then only inpaints (--no-diff) and the lock blurs all).
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
# Moving wallpaper → the frame wallr showed at the grab: a video at the
# position read together with the grab (<grab>.pos, LockScope), a GIF's
# first frame (wallr exposes no GIF position) — extracted like the carousel
# thumbnails (ffmpeg) and then handled as a still image. No frame → kind
# stays moving and the lock just blurs the whole grab.
if [ "$kind" != image ] && [ -n "$wall" ] && [ "$grab" != "-" ]; then
    frame="${grab%.ppm}-wall.jpg"
    seek=""
    [ "$kind" = video ] && seek=$(cat "${grab%.ppm}.pos" 2>/dev/null)
    ffmpeg -nostdin -loglevel error -y ${seek:+-ss "$seek"} -i "$wall" -frames:v 1 -q:v 2 "$frame" 2>/dev/null
    if [ -s "$frame" ]; then
        wall=$frame
        kind=image
    fi
fi
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
