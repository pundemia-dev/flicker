#!/usr/bin/env bash
# Wallpaper carousel thumbnails (plugins/wallpapers/WallpaperService).
# Usage: thumbs.sh <cacheDir> <height> <jobs> <key> <path> [<key> <path> ...]
# Writes <cacheDir>/<key>.jpg (scaled to <height>, aspect kept) for every
# pair, started in the given order (nearest-to-selection first) with up to
# <jobs> ffmpeg runs at once, and prints the key once its file is in place
# ("!key" on failure). Videos: a frame 1 s in (first frame for short clips);
# GIF: first frame. Atomic: render to a temp name, then rename.
set -u
cache=$1 height=$2 jobs=$3
shift 3
mkdir -p "$cache"
# Temp files of killed runs (the launcher closed mid-batch).
find "$cache" -maxdepth 1 -name '.*.jpg' -mmin +1 -delete 2>/dev/null

grab() { # <src> <out> [seek]
    nice -n 10 ffmpeg -nostdin -loglevel error -y ${3:+-ss "$3"} -i "$1" \
        -frames:v 1 -vf "scale=-2:$height" -q:v 3 "$2"
}

one() { # <key> <src>
    local key=$1 src=$2 out="$cache/$1.jpg" tmp="$cache/.$1.$BASHPID.jpg"
    if [ ! -s "$out" ]; then
        case "${src,,}" in
        *.mp4 | *.webm | *.mkv | *.mov)
            # -ss past the end of a short clip exits 0 with no frame
            grab "$src" "$tmp" 1
            [ -s "$tmp" ] || grab "$src" "$tmp"
            ;;
        *) grab "$src" "$tmp" ;;
        esac
        if [ ! -s "$tmp" ]; then
            rm -f "$tmp"
            echo "!$key"
            return
        fi
        mv -f "$tmp" "$out"
    fi
    echo "$key"
}

while [ $# -ge 2 ]; do
    while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do wait -n; done
    one "$1" "$2" &
    shift 2
done
wait
