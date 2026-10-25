#!/usr/bin/env bash
# Output state for services/Displays: wlr-randr's heads (wlr-output-
# management, any compositor) plus niri's own view, which alone says
# whether the current mode is a custom one (wlr lists it like any other).
# Prints {"wlr": [...], "niri": {name: output} | null}; exit 127 without
# wlr-randr.
command -v wlr-randr >/dev/null || exit 127
wlr=$(wlr-randr --json) || exit 1
niri=null
[ -n "$NIRI_SOCKET" ] && niri=$(niri msg --json outputs 2>/dev/null) || niri=null
printf '{"wlr":%s,"niri":%s}\n' "$wlr" "${niri:-null}"
