#!/usr/bin/env bash
# VPN helpers for services/Vpn.qml (QS card `vpn` + its panel): sing-box
# as the system unit `sing-box.service` (runs `sing-box -C /etc/sing-box`,
# i.e. EVERY *.json in that directory is merged — config.json must stay the
# only one). Nodes = the outbounds of the first `selector` outbound, the
# active one = its `default`. Ported from the dots-hyprland (ii)
# virtualprivatenetwork.sh; subscriptions are parsed by sub_parser.py.
# Nodes sing-box cannot carry (gRPC: its lite transport fails against Xray
# servers; XHTTP) go to Xray (xray.service) behind local shadowsocks-2022 ports
# (xray_split.py, keyed), and while there are any xray.service
# starts / stops / restarts with sing-box.
# The configs hold the nodes' secrets: root:<unit user> 0640. What the panel
# needs (nodes, types, the active one, whether Xray is in use, the applied
# routing) is written next to them, secret-free, to /etc/flicker-vpn/view.json
# (0644).
# config.json = compose(base, routing, overlay) (routing.py): base = the
# subscription's config (sub_parser + xray_split, /etc/flicker-vpn/base.json,
# root 0600), routing = the shell's `vpn.routing` (direct / proxy / block
# rules by domain, IP, process, geosite / geoip), overlay = the user's own
# sing-box JSON (~/.config/flicker/vpn/custom.json), applied last. Root keeps
# copies of the applied routing / overlay and the geosite / geoip rule-sets
# (/etc/flicker-vpn/{routing,custom}.json, rules/), so a subscription update
# or a node switch recomposes the same way.
#
#   state              one JSON line: { installed, unit (systemctl
#                      is-active), enabled (autostart), online (a probe
#                      through it answered), profile, profiles:
#                      [{ tag, type }], subscription, killswitch (on),
#                      blocking (its table is up while sing-box is not),
#                      routing (the applied one), customPending (the
#                      overlay file differs from the applied one) }
#   start | stop | restart
#                      systemctl start / stop / restart sing-box (polkit
#                      asks, unless the `setup` rule is installed)
#   enable | disable   autostart at boot (systemctl enable / disable;
#                      polkit always asks — unit files are not in the rule)
#   killswitch on|off  (root via pkexec) the kill switch: while it is on,
#                      starting sing-box also raises flicker-vpn-killswitch
#                      .service (a drop-in `Wants=`), an nftables table that
#                      rejects all outgoing traffic except loopback, the TUN,
#                      sing-box's / Xray's own (by uid) and the LAN (DNS
#                      excepted). It outlives a crashed sing-box: only `stop`
#                      takes it down ("release" in the panel).
#   select <tag>       make <tag> the selector default (root), restart the
#                      unit if it runs
#   subscribe <url>    remember the URL (user state, 0600), download it as
#                      the user, then (root) parse + `sing-box check` +
#                      install config.json, restart the unit if it runs
#   update             subscribe again with the remembered URL
#   apply [json] [refresh]
#                      routing (json = the shell's `vpn.routing`; without it
#                      the last one) + the overlay: validate, download the
#                      geosite / geoip rule-sets it needs (as the user; older
#                      than a day or `refresh` = again), then (root) compose,
#                      `sing-box check`, install, restart the unit if it runs
#   edit               the overlay in $VISUAL / $EDITOR (a skeleton first);
#                      `apply` puts it in force
#   ping              latency of an HTTP probe: "OK:<ms>" / "ERR:"
#   speedtest          speedtest-cli --simple (ERR_MISSING without it)
#   setup              (root, once; again after editing these scripts) a
#                      root-owned copy of them in /usr/local/lib/flicker-vpn
#                      and a polkit rule: the active local session of the
#                      calling user may, without a password, start / stop /
#                      restart sing-box.service, xray.service and the kill
#                      switch unit, and pkexec THE COPY for a node switch
#                      (_select) and a routing-only apply (_reroute) — never
#                      this user-writable script, never an overlay change
#                      or a subscription (those can make sing-box, which
#                      may read any file, serve or route anything).
#
# Root halves run from the copy while it matches these files (else from
# here, which polkit always asks for). What a password-free caller passes
# them is untrusted: routing as a JSON string (a path could name a
# root-only file), rule-set files read without following symlinks and only
# if the caller (PKEXEC_UID) owns them (routing.py install-rules).
set -u

config=/etc/sing-box/config.json
unit=sing-box
xray_config=/etc/xray/config.json
view=/etc/flicker-vpn/view.json
legacy_nodes=/etc/xray/flicker-nodes.tsv
probe=http://cp.cloudflare.com/generate_204
state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/flicker/vpn
sub_file=$state_dir/subscription
routing_file=$state_dir/routing.json
custom_file=${XDG_CONFIG_HOME:-$HOME/.config}/flicker/vpn/custom.json
rules_cache=${XDG_CACHE_HOME:-$HOME/.cache}/flicker/vpn/rules
base=/etc/flicker-vpn/base.json
routing_etc=/etc/flicker-vpn/routing.json
custom_etc=/etc/flicker-vpn/custom.json
rules_etc=/etc/flicker-vpn/rules
rule=/etc/polkit-1/rules.d/50-flicker-vpn.rules
sys_dir=/usr/local/lib/flicker-vpn
sys_files=(vpn.sh routing.py sub_parser.py xray_split.py)
ks_unit=flicker-vpn-killswitch
ks_unit_file=/etc/systemd/system/$ks_unit.service
ks_dropin=/etc/systemd/system/$unit.service.d/flicker-killswitch.conf
ks_rules=/etc/flicker-vpn/killswitch.nft
ks_table="inet flicker_killswitch"
# sub_parser.py names the TUN this; the kill switch lets it through.
tun_name=flicker-tun
self=$(realpath "$0")
here=$(dirname "$self")

err() { echo "ERR:$*"; exit 1; }

# The script pkexec runs: the root-owned copy while it is this one's (the
# password-free rule covers only it), else this one (polkit asks).
root_self() {
    local f
    for f in "${sys_files[@]}"; do
        cmp -s "$here/$f" "$sys_dir/$f" || { echo "$self"; return; }
    done
    echo "$sys_dir/vpn.sh"
}

# Xray carries some nodes (and is installed): it runs alongside sing-box.
uses_xray() {
    command -v xray >/dev/null || return 1
    jq -e '.xray == true' "$view" >/dev/null 2>&1 && return 0
    # Installed before the view existed: its node list.
    [ ! -e "$view" ] && [ -s "$legacy_nodes" ]
}

# sha256 of a file, "" when missing.
hash_of() {
    [ -f "$1" ] && sha256sum <"$1" | cut -c1-64
}

# The panel's view of $config: { profile, profiles: [{ tag, type (shown),
# base, xray, insecure }], xray, routing, customHash }. $1 = nodes moved to
# Xray ("tag<TAB>type<TAB>flags" lines; empty file / none = none).
view_of() {
    local xn='{}' r='{}'
    [ -s "${1:-}" ] && xn=$(jq -Rn '[inputs | split("\t") | select(length >= 2)
        | { key: .[0], value: { base: .[1], insecure: ((.[2] // "") | contains("insecure")) } }] | from_entries' "$1")
    [ -s "$routing_etc" ] && r=$(jq -c . "$routing_etc" 2>/dev/null || echo '{}')
    jq -c --arg ms "$(selector)" --argjson xn "$xn" --argjson r "$r" --arg ch "$(hash_of "$custom_etc")" '
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
            xray: ($xn != {}),
            routing: $r,
            customHash: $ch
        }' "$config"
}

# Root: compose $config's content from base $1 (routing $2, overlay $3) into
# $4, then `sing-box check` it. Prints ERR: and fails on either.
compose() {
    local out
    out=$(python3 -I "$here/routing.py" compose "$1" "$2" "$3" "$rules_etc" "$4") || { echo "$out"; return 1; }
    out=$(sing-box check -c "$4" 2>&1) ||
        { echo "ERR:sing-box: $(printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | tail -n 1)"; return 1; }
}

# Root: the rule-sets routing $1 needs, from the calling user's download
# dir $2 (owned by them, no symlinks: routing.py install-rules) to
# $rules_etc. Ones no longer needed stay until prune_rules (a rollback may
# need them).
install_rules() {
    python3 -I "$here/routing.py" install-rules "$1" "${2:-}" "$rules_etc" "${PKEXEC_UID:--1}"
}

# Root: drop the rule-sets routing $1 does not need (the new config is up).
prune_rules() {
    python3 -I "$here/routing.py" prune-rules "$1" "$rules_etc"
}

# Root: restart the running unit on the just-installed $config and make sure
# it stays up: what `check` cannot see fails only at start. $1 = Xray with
# it: "on" (restart on the new $xray_config), "off" (stop), "" (untouched).
# If it does not come up, the .bak copies go back (the view still describes
# them), the old config is restarted and this fails.
restart_checked() {
    local xr=${1:-} why
    systemctl is-active -q "$unit" || return 0
    case $xr in
    on) systemctl restart xray ;;
    off) systemctl stop xray ;;
    esac
    systemctl restart "$unit" && sleep 3 && systemctl is-active -q "$unit" &&
        { [ "$xr" != on ] || systemctl is-active -q xray; } && return 0
    why=$(journalctl -u "$unit" -u xray -n 20 -o cat --since "-10s" 2>/dev/null | grep -iE 'fatal|error' | tail -n 1 |
        sed 's/\x1b\[[0-9;]*m//g')
    [ -f "$config.bak" ] || err "sing-box did not start with it${why:+: $why}"
    install -m 640 -g "$unit" "$config.bak" "$config"
    if [ -n "$xr" ]; then
        [ "$xr" = on ] && [ -f "$xray_config.bak" ] && install -m 640 -g xray "$xray_config.bak" "$xray_config"
        if uses_xray; then systemctl restart xray; else systemctl stop xray; fi
    fi
    systemctl restart "$unit"
    err "sing-box did not start with it, previous config restored${why:+: $why}"
}

# User: download the rule-sets routing $1 needs to $rules_cache (each from
# the first source that has it); ones younger than a day are kept unless $2.
fetch_rules() {
    local list line f u got
    list=$(python3 -I "$here/routing.py" rulesets "$1") || err "${list#ERR:}"
    [ -n "$list" ] || return 0
    mkdir -p "$rules_cache"
    while IFS= read -r line; do
        IFS=$'\t' read -r -a parts <<<"$line"
        f=${parts[0]}
        [ -z "${2:-}" ] && [ -n "$(find "$rules_cache/$f" -mmin -1440 2>/dev/null)" ] && continue
        got=""
        for u in "${parts[@]:1}"; do
            if curl -4 -sfL --connect-timeout 10 -m 120 "$u" -o "$rules_cache/$f.part" &&
                [ "$(head -c3 "$rules_cache/$f.part")" = SRS ]; then
                mv "$rules_cache/$f.part" "$rules_cache/$f"
                got=1
                break
            fi
        done
        rm -f "$rules_cache/$f.part"
        # A stale copy beats none (GitHub unreachable right now): ours, or
        # root's installed one (install_rules keeps it when we have none).
        [ -n "$got" ] || [ -s "$rules_cache/$f" ] || [ -s "$rules_etc/$f" ] || err "cannot download ${f%.srs}"
    done <<<"$list"
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

# Root: the polkit rule for user $1 (see `setup`).
write_rule() {
    mkdir -p "$(dirname "$rule")"
    cat >"$rule" <<EOF
// Flicker VPN card (scripts/vpn/vpn.sh setup): ${1} may, from the active
// local session and without a password, start / stop ${unit}.service,
// xray.service and ${ks_unit}.service, and run the root-owned
// ${sys_dir}/vpn.sh for a node switch (_select) or a routing-only apply
// (_reroute; the overlay stays root's applied copy).
polkit.addRule(function (action, subject) {
    if (subject.user != "${1}" || !subject.local || !subject.active)
        return polkit.Result.NOT_HANDLED;
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        ["${unit}.service", "xray.service", "${ks_unit}.service"].indexOf(action.lookup("unit")) >= 0 &&
        ["start", "stop", "restart", "try-restart"].indexOf(action.lookup("verb")) >= 0)
        return polkit.Result.YES;
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "${sys_dir}/vpn.sh" &&
        /^\S+ (_select|_reroute) /.test(action.lookup("command_line") || ""))
        return polkit.Result.YES;
    return polkit.Result.NOT_HANDLED;
});
EOF
    chmod 644 "$rule"
}

# Root: the kill switch's ruleset — output only (this host's own traffic).
# The VPN's own paths first, then the LAN minus DNS (the router would
# forward the names to the ISP), then reject (fails fast instead of hanging).
# `ct status dnat`: sing-box's auto_redirect sends TCP to its local port in
# the nat output hook, and the filter hook still sees the pre-NAT interface.
write_ks_rules() {
    local uids
    uids=$(id -u "$unit") || return 1
    id -u xray >/dev/null 2>&1 && uids="$uids, $(id -u xray)"
    mkdir -p "$(dirname "$ks_rules")"
    cat >"$ks_rules" <<EOF
# Flicker VPN kill switch (scripts/vpn/vpn.sh), loaded by ${ks_unit}.service.
table ${ks_table}
delete table ${ks_table}
table ${ks_table} {
    chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" accept
        oifname "${tun_name}" accept
        meta skuid { ${uids} } accept
        ct status dnat accept
        meta l4proto { tcp, udp } th dport { 53, 853 } reject
        ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 } accept
        ip6 daddr { fe80::/10, ff00::/8 } accept
        meta l4proto tcp reject with tcp reset
        reject with icmpx admin-prohibited
    }
}
EOF
    chmod 644 "$ks_rules"
}

ks_on() { [ -e "$ks_dropin" ]; }

# Root: while the kill switch is on, rewrite its table (the uids it lets
# through: Xray may have been installed since it was turned on) and reload
# it if it is up (the file deletes the old table first).
refresh_ks() {
    ks_on || return 0
    write_ks_rules && nft -c -f "$ks_rules" || return 1
    if systemctl is-active -q "$ks_unit"; then nft -f "$ks_rules"; fi
}

# Root: name the TUN of config file $1 $tun_name if it is not yet (one from
# before the TUN had a fixed name): the kill switch lets only that interface
# through. The rest = `install` args for it. 0 = it was renamed.
name_tun() {
    local f=$1 tmp rc
    shift
    [ -r "$f" ] || return 1
    jq -e --arg n "$tun_name" '[.inbounds[]? | select(.type == "tun")] | all(.interface_name == $n)' "$f" >/dev/null &&
        return 1
    tmp=$(mktemp) || return 1
    jq --arg n "$tun_name" '(.inbounds[]? | select(.type == "tun") | .interface_name) = $n' "$f" >"$tmp" &&
        sing-box check -c "$tmp" && install "$@" "$tmp" "$f"
    rc=$?
    rm -f "$tmp"
    return $rc
}

# Tag of the first selector outbound (empty = none).
selector() {
    jq -r '[.outbounds[]? | select(.type == "selector") | .tag][0] // empty' "$config" 2>/dev/null
}

# These go through pkexec: without it its exec fails with 127, which the
# panel would read as a dismissed prompt.
case "${1:-}" in
killswitch | select | subscribe | update | apply)
    command -v pkexec >/dev/null || err "pkexec (polkit) is not installed"
    ;;
esac

case "${1:-}" in
state)
    installed=false
    command -v sing-box >/dev/null && installed=true
    st=$(systemctl is-active "$unit" 2>/dev/null)
    # Up only once both are. Xray dead (not starting) = only its nodes are:
    # the probe through the active one tells (offline after the stall).
    if [ "$st" = active ] && uses_xray; then
        case $(systemctl is-active xray 2>/dev/null) in
        activating | reloading) st=activating ;;
        esac
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
    ks=false
    ks_on && ks=true
    # Traffic held back: the table is up and sing-box is not (crashed,
    # failed, stopped behind Flicker's back).
    blocking=false
    if systemctl is-active -q "$ks_unit" && ! systemctl is-active -q "$unit"; then
        blocking=true
    fi
    # The view; an install from before it existed: the config, if readable.
    v=""
    if [ -r "$view" ]; then
        v=$(cat "$view")
    elif [ -r "$config" ]; then
        v=$(view_of "$legacy_nodes")
    fi
    jq -nc --argjson v "${v:-{\}}" --arg unit "$st" --argjson enabled "$enabled" --argjson installed "$installed" \
        --argjson online "$online" --argjson sub "$sub" --argjson ks "$ks" --argjson blocking "$blocking" \
        --arg ch "$(hash_of "$custom_file")" \
        '{ installed: $installed, unit: $unit, enabled: $enabled, online: $online, subscription: $sub,
        killswitch: $ks, blocking: $blocking, profile: ($v.profile // ""), profiles: ($v.profiles // []),
        routing: ($v.routing // {}), customPending: ($ch != ($v.customHash // "")) }'
    ;;
start | restart | enable | disable)
    # Xray first: sing-box's shadowsocks outbounds point at it. The kill
    # switch (if on) comes up with sing-box by itself (its drop-in).
    if uses_xray; then
        systemctl "$1" xray "$unit" || err "systemctl $1 failed"
    else
        systemctl "$1" "$unit" || err "systemctl $1 failed"
    fi
    ;;
stop)
    # Stop Xray too even if no node needs it any more. A deliberate stop is
    # the one thing that lowers the kill switch (also after a crash).
    units=("$unit")
    systemctl is-active -q xray && units+=(xray)
    systemctl is-active -q "$ks_unit" && units+=("$ks_unit")
    systemctl stop "${units[@]}" || err "systemctl stop failed"
    ;;
killswitch)
    case "${2:-}" in
    on | off) ;;
    *) err "usage: killswitch on|off" ;;
    esac
    exec pkexec "$(root_self)" _killswitch "$2" "$(id -un)"
    ;;
select)
    [ -n "${2:-}" ] || err "usage: select <tag>"
    exec pkexec "$(root_self)" _select "$2"
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
    # The applied routing's rule-sets, refreshed along with the nodes.
    [ -s "$routing_etc" ] && fetch_rules "$routing_etc"
    pkexec "$(root_self)" _apply "$raw" "$rules_cache"
    ;;
apply)
    mkdir -p "$state_dir"
    [ -n "${2:-}" ] && printf '%s\n' "$2" >"$routing_file"
    [ -s "$routing_file" ] || echo '{}' >"$routing_file"
    out=$(python3 -I "$here/routing.py" check "$routing_file" "$custom_file") || err "${out#ERR:}"
    fetch_rules "$routing_file" "${3:-}"
    # The overlay as applied (the view's hash of root's copy): routing only,
    # password-free with `setup` done; a changed overlay always asks.
    if [ "$(hash_of "$custom_file")" = "$(jq -r '.customHash // ""' "$view" 2>/dev/null)" ]; then
        exec pkexec "$(root_self)" _reroute "$(cat "$routing_file")" "$rules_cache"
    fi
    exec pkexec "$(root_self)" _routing "$(cat "$routing_file")" "$custom_file" "$rules_cache"
    ;;
edit)
    if [ ! -e "$custom_file" ]; then
        mkdir -p "$(dirname "$custom_file")"
        # Merged over the generated config (routing.py): rules here go first.
        printf '%s\n' '{' '  "route": { "rules": [] },' '  "dns": { "rules": [] }' '}' >"$custom_file"
    fi
    ed=${VISUAL:-${EDITOR:-}}
    if [ -z "$ed" ]; then
        for e in nvim vim nano vi; do
            command -v "$e" >/dev/null && { ed=$e; break; }
        done
    fi
    # shellcheck disable=SC2086 # "$EDITOR" may carry flags
    exec $ed "$custom_file"
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
    install -d -m 755 "$sys_dir"
    [ "$here" != "$sys_dir" ] && for f in "${sys_files[@]}"; do
        install -m 755 -o root -g root "$here/$f" "$sys_dir/$f" || err "cannot install $f"
    done
    write_rule "${2:?user}"
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
    tmp=$(mktemp) && btmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$btmp"' EXIT
    sel='(.outbounds[] | select(.type == "selector" and .tag == $ms) | .default) = $tag'
    jq --arg ms "$ms" --arg tag "$2" "$sel" "$config" >"$tmp" || err "jq failed"
    # The base too (first: if the config then fails, the next recompose
    # still picks the node), or the next recompose would switch back.
    if [ -f "$base" ]; then
        jq --arg ms "$ms" --arg tag "$2" "$sel" "$base" >"$btmp" || err "jq failed on $base"
        install -m 600 "$btmp" "$base" || err "cannot update $base"
    fi
    install -m 640 -g "$unit" "$tmp" "$config" || err "cannot update $config"
    write_view || err "view update failed"
    systemctl try-restart "$unit" || err "restart failed"
    echo "OK:$2"
    ;;
_killswitch)
    [ "$(id -u)" -eq 0 ] || err "root only"
    if [ "$2" = on ]; then
        command -v nft >/dev/null || err "nft (nftables) is not installed"
        write_ks_rules || err "no $unit user"
        nft -c -f "$ks_rules" || err "nft rejected the kill switch rules"
        cat >"$ks_unit_file" <<EOF
# Flicker VPN kill switch (scripts/vpn/vpn.sh): pulled in by ${unit}.service,
# stopped only by "vpn.sh stop" — it outlives a crashed sing-box.
[Unit]
Description=Flicker VPN kill switch
Before=${unit}.service xray.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nft -f ${ks_rules}
ExecStop=-/usr/bin/nft delete table ${ks_table}
EOF
        mkdir -p "$(dirname "$ks_dropin")"
        printf '[Unit]\nWants=%s.service\n' "$ks_unit" >"$ks_dropin"
        # A config from before the TUN had a fixed name: name it, or the
        # table would block the VPN's own interface. The base too, or the
        # next recompose would bring the old name back.
        [ -f "$base" ] && name_tun "$base" -m 600
        name_tun "$config" -m 640 -g "$unit" && systemctl try-restart "$unit"
        # The password-free rule (if installed) learns the new unit.
        [ -e "$rule" ] && [ -n "${3:-}" ] && write_rule "$3"
        systemctl daemon-reload
        if systemctl is-active -q "$unit"; then
            systemctl start "$ks_unit" || err "kill switch failed to start"
        fi
    else
        systemctl stop "$ks_unit" 2>/dev/null
        rm -f "$ks_dropin"
        rmdir "$(dirname "$ks_dropin")" 2>/dev/null
        systemctl daemon-reload
    fi
    echo "OK:killswitch $2"
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
    # $tmp = the new base; the config = it + the applied routing / overlay.
    install_rules "$routing_etc" "${3:-}" || err "rule-set install failed"
    ctmp=$(mktemp) || err "mktemp"
    trap 'rm -f "$tmp" "$xtmp" "$ntmp" "$etmp" "$ctmp"' EXIT
    out=$(compose "$tmp" "$routing_etc" "$custom_etc" "$ctmp") || err "${out#ERR:}"
    if [ -s "$ntmp" ]; then
        # Format by extension otherwise, and mktemp names have none.
        out=$(xray run -test -format json -config "$xtmp" 2>&1) ||
            err "xray rejected the generated config: $(printf '%s' "$out" | grep -v 'Reading config' | tail -n 1)"
    fi
    mkdir -p "$(dirname "$config")"
    # Backups hold the same secrets: root only.
    # Xray's uid may be new to the kill switch: let it through before it runs.
    refresh_ks || err "kill switch update failed"
    [ -f "$config" ] && install -m 600 "$config" "$config.bak"
    install -m 640 -g "$unit" "$ctmp" "$config"
    xr=off
    if [ -s "$ntmp" ]; then
        xr=on
        mkdir -p "$(dirname "$xray_config")"
        [ -f "$xray_config" ] && install -m 600 "$xray_config" "$xray_config.bak"
        install -m 640 -g xray "$xtmp" "$xray_config"
    fi
    # Base and view only once it is up: a rollback keeps the old ones.
    restart_checked "$xr"
    mkdir -p "$(dirname "$base")"
    install -m 600 "$tmp" "$base"
    write_view "$ntmp" || err "view update failed"
    rm -f "$legacy_nodes"
    prune_rules "$routing_etc"
    echo "OK:applied"
    ;;
_routing | _reroute)
    [ "$(id -u)" -eq 0 ] || err "root only"
    # $2 the routing (JSON text, not a path: a password-free caller could
    # name a root-only file, which would end up 0644 in $routing_etc).
    # _routing (polkit asks): $3 the user's overlay (may be missing), $4 the
    # rule-set downloads. _reroute (password-free): $3 the downloads; the
    # overlay is the applied one, untouched.
    tmps=()
    trap 'rm -f "${tmps[@]}"' EXIT
    rtmp=$(mktemp) && otmp=$(mktemp) && ctmp=$(mktemp) || err "mktemp"
    tmps=("$rtmp" "$otmp" "$ctmp")
    printf '%s\n' "${2:-}" >"$rtmp"
    if [ "$1" = _routing ]; then
        dl=${4:-}
        [ ! -L "${3:-}" ] || err "$3 is a symlink"
        if [ -f "${3:-}" ]; then cat -- "$3" >"$otmp" || err "cannot read $3"; else otmp=""; fi
    else
        dl=${3:-}
        if [ -f "$custom_etc" ]; then cat "$custom_etc" >"$otmp"; else otmp=""; fi
    fi
    out=$(python3 -I "$here/routing.py" check "$rtmp" "$otmp") || err "${out#ERR:}"
    # Before the base existed the config was one (nothing composed in yet).
    b=$base
    [ -f "$b" ] || b=$config
    [ -f "$b" ] || err "no config yet: import a subscription first"
    # A base from before the TUN had a fixed name (the kill switch needs it).
    [ -f "$base" ] && name_tun "$base" -m 600
    install_rules "$rtmp" "$dl" || err "rule-set install failed"
    out=$(compose "$b" "$rtmp" "$otmp" "$ctmp") || err "${out#ERR:}"
    mkdir -p "$(dirname "$base")"
    [ -f "$base" ] || install -m 600 "$config" "$base"
    [ -f "$config" ] && install -m 600 "$config" "$config.bak"
    install -m 640 -g "$unit" "$ctmp" "$config"
    # If it does not come up, the copies below stay the old ones, so the
    # change is still pending.
    restart_checked
    install -m 644 "$rtmp" "$routing_etc"
    prune_rules "$rtmp"
    # The overlay may name its own servers / keys: root only.
    if [ "$1" = _routing ]; then
        if [ -n "$otmp" ]; then install -m 600 "$otmp" "$custom_etc"; else rm -f "$custom_etc"; fi
    fi
    write_view || err "view update failed"
    echo "OK:routing applied"
    ;;
*)
    sed -n '2,/^set -u$/{/^set -u$/!p}' "$self"
    exit 2
    ;;
esac
