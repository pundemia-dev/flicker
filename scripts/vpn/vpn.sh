#!/usr/bin/env bash
# VPN helpers for services/Vpn.qml (QS card `vpn` + its panel): sing-box
# as the system unit `sing-box.service` (runs `sing-box -C /etc/sing-box`,
# i.e. EVERY *.json in that directory is merged — config.json must stay the
# only one). Nodes = the outbounds of the first `selector` outbound, the
# active one = its `default`. Ported from the dots-hyprland (ii)
# virtualprivatenetwork.sh; subscriptions are parsed by sub_parser.py.
# Nodes sing-box cannot carry (gRPC: its lite transport fails against Xray
# servers; XHTTP) go to Xray (xray.service) behind local SOCKS ports
# (xray_split.py, password-protected), and while there are any xray.service
# starts / stops / restarts with sing-box.
# The configs hold the nodes' secrets: root:<unit user> 0640. What the panel
# needs (nodes, types, the active one, whether Xray is in use) is written
# next to them, secret-free, to /etc/flicker-vpn/view.json (0644).
#
#   state              one JSON line: { installed, unit (systemctl
#                      is-active), enabled (autostart), online (a probe
#                      through it answered), profile, profiles:
#                      [{ tag, type }], subscription }
#   start | stop | restart
#                      systemctl start / stop / restart sing-box (polkit
#                      asks, unless the `setup` rule is installed)
#   enable | disable   autostart at boot (systemctl enable / disable;
#                      polkit always asks — unit files are not in the rule)
#   select <tag>       make <tag> the selector default (root), restart the
#                      unit if it runs
#   subscribe <url>    remember the URL (user state, 0600), download it as
#                      the user, then (root) parse + `sing-box check` +
#                      install config.json, restart the unit if it runs
#   update             subscribe again with the remembered URL
#   ping               latency of an HTTP probe: "OK:<ms>" / "ERR:"
#   speedtest          speedtest-cli --simple (ERR_MISSING without it)
#   setup              (root, once) polkit rule: the active local session of
#                      the calling user may start / stop / restart
#                      sing-box.service and xray.service without a password. Deliberately NOT
#                      "pkexec this script without a password": the script
#                      lives in a user-writable directory.
set -u

config=/etc/sing-box/config.json
unit=sing-box
xray_config=/etc/xray/config.json
view=/etc/flicker-vpn/view.json
legacy_nodes=/etc/xray/flicker-nodes.tsv
probe=http://cp.cloudflare.com/generate_204
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/flicker/vpn
sub_file=$state_dir/subscription
rule=/etc/polkit-1/rules.d/50-flicker-vpn.rules
self=$(realpath "$0")
here=$(dirname "$self")

err() { echo "ERR:$*"; exit 1; }

# Xray carries some nodes (and is installed): it runs alongside sing-box.
uses_xray() {
    command -v xray >/dev/null || return 1
    jq -e '.xray == true' "$view" >/dev/null 2>&1 && return 0
    # Installed before the view existed: its node list.
    [ ! -e "$view" ] && [ -s "$legacy_nodes" ]
}

# The panel's view of $config: { profile, profiles: [{ tag, type (shown),
# base, xray, insecure }], xray }. $1 = nodes moved to Xray
# ("tag<TAB>type<TAB>flags" lines; empty file / none = none).
view_of() {
    local xn='{}'
    [ -s "${1:-}" ] && xn=$(jq -Rn '[inputs | split("\t") | select(length >= 2)
        | { key: .[0], value: { base: .[1], insecure: ((.[2] // "") | contains("insecure")) } }] | from_entries' "$1")
    jq -c --arg ms "$(selector)" --argjson xn "$xn" '
        . as $c
        | ([$c.outbounds[]?, $c.endpoints[]?] | map(select(.tag | type == "string") | { key: .tag, value: .type }) | from_entries) as $types
        | ([$c.outbounds[]? | select(.type == "selector" and .tag == $ms)][0]) as $sel
        | def node($t): ($xn[$t]) as $x
            | if $x then { tag: $t, base: $x.base, xray: true, insecure: $x.insecure,
                           type: ($x.base + " · xray" + (if $x.insecure then " · ⚠ cert checked" else "" end)) }
              else { tag: $t, base: ($types[$t] // ""), xray: false, insecure: false, type: ($types[$t] // "") } end;
        {
            profile: (if $sel then ($sel.default // $sel.outbounds[0] // "") else "" end),
            profiles: (if $sel then [$sel.outbounds[]? | node(.)] else [] end),
            xray: ($xn != {})
        }' "$config"
}

# Root: rewrite the view from $config. $1 = the Xray node list of a fresh
# apply; without one the current view's is kept (a node switch).
write_view() {
    local nodes=${1:-} own="" tmp
    if [ -z "$nodes" ] && [ -r "$view" ]; then
        own=$(mktemp) || return 1
        # (A view from before base / xray existed: parse the shown type.)
        jq -r '.profiles[] | select(.xray // (.type | endswith(" · xray")))
            | "\(.tag)\t\(.base // (.type | rtrimstr(" · xray")))\t\(if .insecure then "insecure" else "" end)"' "$view" >"$own"
        nodes=$own
    fi
    tmp=$(mktemp) || return 1
    local ok=0
    view_of "$nodes" >"$tmp" && mkdir -p "$(dirname "$view")" && install -m 644 "$tmp" "$view" || ok=1
    rm -f "$tmp" $own
    return $ok
}

# Tag of the first selector outbound (empty = none).
selector() {
    jq -r '[.outbounds[]? | select(.type == "selector") | .tag][0] // empty' "$config" 2>/dev/null
}

case "${1:-}" in
state)
    installed=false
    command -v sing-box >/dev/null && installed=true
    st=$(systemctl is-active "$unit" 2>/dev/null)
    # Up only once both are: Xray down = its nodes are dead.
    if [ "$st" = active ] && uses_xray && ! systemctl is-active -q xray; then
        st=activating
    fi
    enabled=false
    [ "$(systemctl is-enabled "$unit" 2>/dev/null)" = enabled ] && enabled=true
    online=false
    # IPv6 is broken on some hosts: -4.
    if [ "$st" = active ] && curl -4 -s -o /dev/null --connect-timeout 1 -m 2 "$probe"; then
        online=true
    fi
    sub=false
    [ -s "$sub_file" ] && sub=true
    # The view; an install from before it existed: the config, if readable.
    v=""
    if [ -r "$view" ]; then
        v=$(cat "$view")
    elif [ -r "$config" ]; then
        v=$(view_of "$legacy_nodes")
    fi
    jq -nc --argjson v "${v:-{\}}" --arg unit "$st" --argjson enabled "$enabled" --argjson installed "$installed" \
        --argjson online "$online" --argjson sub "$sub" '{ installed: $installed, unit: $unit, enabled: $enabled,
        online: $online, subscription: $sub, profile: ($v.profile // ""), profiles: ($v.profiles // []) }'
    ;;
start | restart | enable | disable)
    # Xray first: sing-box's socks outbounds point at it.
    if uses_xray; then
        systemctl "$1" xray "$unit" || err "systemctl $1 failed"
    else
        systemctl "$1" "$unit" || err "systemctl $1 failed"
    fi
    ;;
stop)
    # Stop Xray too even if no node needs it any more.
    if systemctl is-active -q xray; then
        systemctl stop "$unit" xray || err "systemctl stop failed"
    else
        systemctl stop "$unit" || err "systemctl stop failed"
    fi
    ;;
select)
    [ -n "${2:-}" ] || err "usage: select <tag>"
    exec pkexec "$self" _select "$2"
    ;;
subscribe)
    url=${2:-}
    case "$url" in
    http://* | https://*) ;;
    *) err "not an http(s) URL" ;;
    esac
    mkdir -p "$state_dir"
    (umask 077 && printf '%s' "$url" >"$sub_file")
    raw=$(mktemp) || err "mktemp"
    trap 'rm -f "$raw"' EXIT
    curl -4 -sfL -m 20 -A sing-box "$url" -o "$raw" || err "download failed"
    [ -s "$raw" ] || err "empty subscription"
    pkexec "$self" _apply "$raw"
    ;;
update)
    [ -s "$sub_file" ] || err "no subscription"
    exec "$self" subscribe "$(cat "$sub_file")"
    ;;
ping)
    t=$(curl -4 -s -o /dev/null -w '%{time_total}' --connect-timeout 5 -m 6 "$probe") || err "timeout"
    echo "OK:$(awk -v t="$t" 'BEGIN { printf "%d", t * 1000 }')"
    ;;
speedtest)
    command -v speedtest-cli >/dev/null || { echo ERR_MISSING; exit 1; }
    speedtest-cli --simple 2>/dev/null || { echo ERR_FAILED; exit 1; }
    ;;
setup)
    [ "$(id -u)" -eq 0 ] || exec pkexec "$self" setup "$(id -un)"
    user=${2:?user}
    mkdir -p "$(dirname "$rule")"
    cat >"$rule" <<EOF
// Flicker VPN card (scripts/vpn/vpn.sh setup): ${user} may start / stop
// ${unit}.service and xray.service from the active local session without a
// password.
polkit.addRule(function (action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        ["${unit}.service", "xray.service"].indexOf(action.lookup("unit")) >= 0 &&
        ["start", "stop", "restart", "try-restart"].indexOf(action.lookup("verb")) >= 0 &&
        subject.user == "${user}" && subject.local && subject.active)
        return polkit.Result.YES;
});
EOF
    chmod 644 "$rule"
    echo "OK:$rule"
    ;;

# Root halves (pkexec) -------------------------------------------------------
_select)
    [ "$(id -u)" -eq 0 ] || err "root only"
    ms=$(selector)
    [ -n "$ms" ] || err "no selector outbound in $config"
    jq -e --arg ms "$ms" --arg tag "$2" \
        '.outbounds[] | select(.type == "selector" and .tag == $ms) | .outbounds | index($tag) != null' \
        "$config" >/dev/null || err "no node $2"
    tmp=$(mktemp) || err "mktemp"
    jq --arg ms "$ms" --arg tag "$2" \
        '(.outbounds[] | select(.type == "selector" and .tag == $ms) | .default) = $tag' \
        "$config" >"$tmp" || { rm -f "$tmp"; err "jq failed"; }
    install -m 640 -g "$unit" "$tmp" "$config" && rm -f "$tmp"
    write_view || err "view update failed"
    systemctl try-restart "$unit" || err "restart failed"
    echo "OK:$2"
    ;;
_apply)
    [ "$(id -u)" -eq 0 ] || err "root only"
    # Not *.json and not in /etc/sing-box: the unit merges every *.json there.
    tmp=$(mktemp) || err "mktemp"
    xtmp=$(mktemp) || err "mktemp"
    ntmp=$(mktemp) || err "mktemp"
    etmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$xtmp" "$ntmp" "$etmp"' EXIT
    python3 -I "$here/sub_parser.py" "$tmp" "$2" "$etmp" || err "no nodes in the subscription"
    # Keep the chosen node across an update (the parser defaults to the first,
    # often a provider's placeholder) if the new subscription still has it.
    keep=$([ -r "$config" ] && jq -r --arg ms "$(selector)" \
        '[.outbounds[]? | select(.type == "selector" and .tag == $ms) | .default][0] // empty' "$config")
    if [ -n "$keep" ]; then
        jq --arg tag "$keep" '(.outbounds[] | select(.type == "selector" and (.outbounds | index($tag) != null)) | .default) = $tag' \
            "$tmp" >"$tmp.keep" && mv "$tmp.keep" "$tmp"
    fi
    # gRPC / XHTTP nodes to Xray (only when it is installed).
    if xuid=$(id -u xray 2>/dev/null) && command -v xray >/dev/null; then
        python3 -I "$here/xray_split.py" "$tmp" "$xtmp" "$ntmp" "$xuid" "$etmp" || err "xray split failed"
    fi
    sing-box check -c "$tmp" || err "sing-box rejected the generated config"
    if [ -s "$ntmp" ]; then
        # Format by extension otherwise, and mktemp names have none.
        out=$(xray run -test -format json -config "$xtmp" 2>&1) ||
            err "xray rejected the generated config: $(printf '%s' "$out" | grep -v 'Reading config' | tail -n 1)"
    fi
    mkdir -p "$(dirname "$config")"
    # Backups hold the same secrets: root only.
    [ -f "$config" ] && install -m 600 "$config" "$config.bak"
    install -m 640 -g "$unit" "$tmp" "$config"
    if [ -s "$ntmp" ]; then
        mkdir -p "$(dirname "$xray_config")"
        [ -f "$xray_config" ] && install -m 600 "$xray_config" "$xray_config.bak"
        install -m 640 -g xray "$xtmp" "$xray_config"
    fi
    write_view "$ntmp" || err "view update failed"
    rm -f "$legacy_nodes"
    if systemctl is-active -q "$unit"; then
        if [ -s "$ntmp" ]; then
            systemctl restart xray || err "xray restart failed"
        else
            systemctl stop xray
        fi
    fi
    systemctl try-restart "$unit" || err "restart failed"
    echo "OK:applied"
    ;;
*)
    sed -n '2,30p' "$self"
    exit 2
    ;;
esac
