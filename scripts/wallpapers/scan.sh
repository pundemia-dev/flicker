#!/usr/bin/env bash
# Wallpaper directory scan (plugins/wallpapers/WallpaperService).
# Usage: scan.sh files|sig <recursive 0|1> <dir> [<dir> ...]
#   files: "<mtime>\t<size>\t<path>" per wallpaper (image/GIF/video by
#          extension); dot files and dot dirs (.git) are skipped.
#   sig:   one line of directory mtimes — changes whenever an entry is
#          added/removed/renamed, so the service rescans only then.
set -u
mode=$1 rec=$2
shift 2
depth=()
[ "$rec" = 1 ] || depth=(-maxdepth 1)
for d in "$@"; do
    d=${d/#\~/$HOME}
    [ -d "$d" ] || continue
    if [ "$mode" = sig ]; then
        find "$d" "${depth[@]}" -mindepth 0 \( -name '.*' -not -path "$d" -prune \) -o -type d -printf '%T@ '
    else
        find "$d" "${depth[@]}" -mindepth 1 -name '.*' -prune -o -type f \( \
            -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o \
            -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.tga' -o \
            -iname '*.gif' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' \
            \) -printf '%T@\t%s\t%p\n'
    fi
done
[ "$mode" = sig ] && echo
exit 0
