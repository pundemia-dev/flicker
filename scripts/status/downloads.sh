#!/usr/bin/env bash
# In-progress downloads for the status drop (services/DownloadWatch.qml).
# Usage: downloads.sh <fresh-minutes> <browser-dir> [model-dir ...]
# One line per partial file touched within <fresh-minutes> (a killed
# download leaves its partial behind — stale ones are not "running"):
#   b<TAB><bytes><TAB><path>   browser (.part = Firefox, .crdownload = Chromium)
#   m<TAB><bytes><TAB><path>   model weights (HF hub .incomplete, torch hub .partial)
fresh="$1"
browser="$2"
shift 2
[ -d "$browser" ] && find "$browser" -maxdepth 1 -type f \( -name '*.part' -o -name '*.crdownload' \) \
    -mmin "-$fresh" -printf 'b\t%s\t%p\n' 2>/dev/null
for d in "$@"; do
    [ -d "$d" ] || continue
    find "$d" -maxdepth 4 -type f \( -name '*.incomplete' -o -name '*.partial' \) \
        -mmin "-$fresh" -printf 'm\t%s\t%p\n' 2>/dev/null
done
true
