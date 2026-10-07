#!/usr/bin/env bash
# Current wallpaper of an output as the carousel knows it: wallr's state
# file, mapped back from a fill-blur composite (setwall.sh) to the original.
# Usage: current.sh <output>
p=$(cat "$HOME/.cache/wallr/last_wallpaper/$1" 2>/dev/null) || exit 0
src="${p%.jpg}.src"
case "$p" in
*/fill/*.jpg) [ -s "$src" ] && p=$(cat "$src") ;;
esac
printf '%s\n' "$p"
