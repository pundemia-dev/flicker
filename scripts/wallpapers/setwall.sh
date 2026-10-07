#!/usr/bin/env bash
# Set a wallpaper on one output through wallr, with adaptive fill-blur
# (services/Wallpaper; idea from walltool's resize "adaptive"/fill-blur).
# Usage: setwall.sh <src> <outW> <outH> <threshold|0> <sigma> <dim> <cacheDir> -- <wallr set args without the path>
# A still image whose aspect differs from the output's by more than
# `threshold` (min(a/b, b/a) < threshold; 0 = never) is shown WHOLE, centred
# over a blurred, darkened (dim 0..1) cover-fit copy of itself, composed at
# the output's pixel size and cached as <cacheDir>/fill/<md5>.jpg (+ .src =
# the original path, so the carousel can find the real file again).
# Anything else (GIF, video, matching aspect) goes to wallr unchanged.
set -u
src=$1 W=$2 H=$3 thr=$4 sigma=$5 dim=$6 cache=$7
shift 7
[ "${1:-}" = "--" ] && shift
path=$src
case "${src,,}" in
*.gif | *.mp4 | *.webm | *.mkv | *.mov) ;;
*)
    if [ "$thr" != "0" ] && [ "$W" -gt 0 ] && [ "$H" -gt 0 ]; then
        read -r iw ih < <(magick identify -format '%w %h\n' "$src[0]" 2>/dev/null | head -1)
        if [ -n "${iw:-}" ] && [ "${ih:-0}" -gt 0 ] &&
            awk -v iw="$iw" -v ih="$ih" -v W="$W" -v H="$H" -v t="$thr" \
                'BEGIN { a = iw / ih; b = W / H; r = a < b ? a / b : b / a; exit !(r < t) }'; then
            stamp=$(stat -c '%Y %s' -- "$src")
            key=$(printf '%s|%s|%sx%s|%s|%s' "$src" "$stamp" "$W" "$H" "$sigma" "$dim" | md5sum | cut -c1-32)
            out="$cache/fill/$key.jpg"
            if [ ! -s "$out" ]; then
                mkdir -p "$cache/fill"
                tmp="$cache/fill/.$key.$$.jpg"
                bright=$(awk -v d="$dim" 'BEGIN { printf "%d", (1 - d) * 100 }')
                # Background: cover-fit, blurred at 1/8 size (fast), back up.
                magick "$src[0]" -auto-orient -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" \
                    -resize 12.5% -blur "0x$sigma" -resize "${W}x${H}!" -modulate "$bright" \
                    \( "$src[0]" -auto-orient -resize "${W}x${H}" \) -gravity center -composite \
                    -quality 92 "$tmp" && mv -f "$tmp" "$out" && printf '%s\n' "$src" > "$cache/fill/$key.src"
                rm -f "$tmp"
            fi
            [ -s "$out" ] && path=$out
        fi
    fi
    ;;
esac
exec wallr set "$path" "$@"
