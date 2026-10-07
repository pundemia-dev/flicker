#!/usr/bin/env bash
# Hide / unhide a wallpaper (services/Wallpaper.setHidden): rename
# <dir>/<name> <-> <dir>/.<name>. Usage: hide.sh <src> <dest>
# Prints the resulting path, or "!<reason>" on failure.
#   dest free           → mv
#   dest = same bytes   → src is a duplicate of it: src goes to the trash
#                          (gio trash, recoverable), dest stays
#   dest = other file   → a free name "<stem>-<n>.<ext>" next to dest
# Never overwrites anything.
set -u
src=$1 dest=$2
[ -e "$src" ] || { echo "!missing"; exit 1; }
if [ ! -e "$dest" ]; then
    mv -n -- "$src" "$dest" && [ -e "$dest" ] && [ ! -e "$src" ] && { echo "$dest"; exit 0; }
    echo "!mv"; exit 1
fi
if cmp -s -- "$src" "$dest"; then
    gio trash -- "$src" && { echo "$dest"; exit 0; }
    echo "!trash"; exit 1
fi
dir=${dest%/*} base=${dest##*/}
stem=${base%.*} ext=${base##*.}
[ "$stem" = "$base" ] && ext="" || ext=".$ext"
for n in $(seq 2 999); do
    alt="$dir/$stem-$n$ext"
    if [ ! -e "$alt" ]; then
        mv -n -- "$src" "$alt" && [ ! -e "$src" ] && { echo "$alt"; exit 0; }
        echo "!mv"; exit 1
    fi
done
echo "!names"; exit 1
