#!/usr/bin/env bash
# Lock-screen avatar: path + kind (image | animated | video), one tab-separated
# line. Kind comes from the MIME type, not the extension (~/.face has none).
# Usage: avatar.sh [path]   (empty = ~/.face, ~/.face.icon, AccountsService)
set -u
p=${1:-}
p=${p/#\~/$HOME}
if [ -z "$p" ]; then
    for c in "$HOME/.face" "$HOME/.face.icon" "/var/lib/AccountsService/icons/$USER"; do
        [ -r "$c" ] && { p=$c; break; }
    done
fi
[ -n "$p" ] && [ -r "$p" ] || exit 1
p=$(readlink -f -- "$p")
mime=$(file -Lb --mime-type -- "$p")
case "$mime" in
image/gif | image/webp | image/apng) kind=animated ;;
video/*) kind=video ;;
image/*) kind=image ;;
*) exit 1 ;;
esac
printf '%s\t%s\n' "$p" "$kind"
