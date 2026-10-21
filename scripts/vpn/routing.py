#!/usr/bin/env python3
# Split routing + the user's own config overlay for sing-box (vpn.sh).
#
# Routing (config.json `vpn.routing`, edited by the settings window):
#   { "final": "proxy" | "direct",
#     "rules": [ { "action": "proxy" | "direct" | "block",
#                  "match": ["geoip:ru", "geosite:category-ru", "domain:example.com",
#                            "process:steam", ...] }, ... ] }
# Rules are tried in order, the first match wins; within a rule any matcher
# may match. Matchers:
#   domain:<d>   d and its subdomains        full:<d>     exactly d
#   keyword:<s>  domain contains s           regexp:<re>  domain regex
#   ip:<cidr>    destination address         process:<n>  executable name
#   path:<p>     executable path             protocol:<p> sniffed (bittorrent,
#                                                         quic, stun, ...)
#   geosite:<name>[@source]   geoip:<name>[@source]
#   a bare value = ip: if it parses as an address / CIDR, else domain:.
# geosite / geoip are binary rule-sets (.srs) from SOURCES, tried in order
# unless @source pins one; vpn.sh downloads them (`rulesets`), compose reads
# them from the rules dir. LAN (private addresses) always goes direct.
# DNS follows the route: domains routed direct resolve through dns-direct
# (CDNs answer with nearby addresses), proxied ones through dns-remote,
# blocked ones are refused.
#
# Overlay (the user's own sing-box JSON, applied last, wins over everything):
# objects merge recursively, `null` deletes a key, arrays of tagged objects
# (outbounds, endpoints, inbounds, dns.servers, route.rule_set) merge by tag
# (same tag = replaced), route.rules / dns.rules are put in front of the
# generated ones (after the sniff / hijack-dns rules and Xray's uid rule),
# other arrays replace. The result's tag references (outbounds, DNS servers,
# rule-sets) are checked: `sing-box check` does not, sing-box fails at start.
#
#   routing.py check <routing.json> [overlay.json]       exit 1 + message
#   routing.py rulesets <routing.json>                   "file<TAB>url..." lines
#   routing.py compose <base.json> <routing.json> <overlay.json> <rules dir> <out>
#   routing.py install-rules <routing.json> <user dir> <rules dir> <uid>
#                                (root) the rule-sets the routing needs from
#                                the user's downloads, others removed
# Missing routing / overlay files = none (everything through the proxy).

import ipaddress
import json
import os
import re
import stat
import sys

SOURCES = {
    "runetfreedom": {
        "geosite": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-{}.srs",
        "geoip": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geoip/geoip-{}.srs",
    },
    "metacubex": {
        "geosite": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geosite/{}.srs",
        "geoip": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo/geoip/{}.srs",
    },
    "sagernet": {
        "geosite": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-{}.srs",
        "geoip": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-{}.srs",
    },
}
SOURCE_ORDER = ("runetfreedom", "metacubex", "sagernet")
ACTIONS = ("proxy", "direct", "block")
# Matcher prefix -> headless rule field (inline rule-sets).
FIELDS = {
    "domain": "domain_suffix", "full": "domain", "keyword": "domain_keyword",
    "regexp": "domain_regex", "ip": "ip_cidr", "process": "process_name",
    "path": "process_path",
}
DNS_FIELDS = ("domain_suffix", "domain", "domain_keyword", "domain_regex")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._!-]*$")
PREFIX = "flicker-"


class Bad(Exception):
    pass


def load(path, default):
    if not path or not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        return default
    try:
        return json.loads(text)
    except ValueError as e:
        raise Bad("%s: %s" % (os.path.basename(path), e))


def is_ip(v):
    try:
        ipaddress.ip_network(v, strict=False)
        return True
    except ValueError:
        return False


def parse(m):
    """matcher string -> (kind, value, source)"""
    if not isinstance(m, str) or not m.strip():
        raise Bad("empty matcher")
    m = m.strip()
    kind, sep, value = m.partition(":")
    if not sep or kind not in FIELDS and kind not in ("geosite", "geoip", "protocol"):
        # Bare value (an IPv6 address has colons but no known prefix).
        kind, value = ("ip", m) if is_ip(m) else ("domain", m)
    value = value.strip()
    if not value:
        raise Bad("%s: empty value" % m)
    source = ""
    if kind in ("geosite", "geoip"):
        value, _, source = value.lower().partition("@")
        if not NAME_RE.match(value):
            raise Bad("%s: bad list name" % m)
        if source and source not in SOURCES:
            raise Bad("%s: unknown source (%s)" % (m, ", ".join(SOURCE_ORDER)))
    elif kind == "ip" and not is_ip(value):
        raise Bad("%s: not an address / CIDR" % m)
    elif kind == "regexp":
        try:
            re.compile(value)
        except re.error as e:
            raise Bad("%s: %s" % (m, e))
    return kind, value, source


def rules_of(routing):
    if not isinstance(routing, dict):
        raise Bad("routing: not an object")
    final = routing.get("final", "proxy")
    if final not in ("proxy", "direct"):
        raise Bad("routing.final: proxy | direct")
    out = []
    for i, r in enumerate(routing.get("rules") or []):
        if not isinstance(r, dict) or r.get("action") not in ACTIONS:
            raise Bad("rule %d: action must be %s" % (i + 1, " | ".join(ACTIONS)))
        if r.get("enabled", True) is False:
            continue
        match = r.get("match") or []
        if isinstance(match, str):
            match = [match]
        out.append((r["action"], [parse(m) for m in match]))
    return final, out


def ruleset_file(kind, name, source):
    return "%s-%s%s.srs" % (kind, name, "@" + source if source else "")


def rulesets(routing):
    """Unique (file, [urls]) the routing needs, in rule order."""
    seen, out = set(), []
    for _, matchers in rules_of(routing)[1]:
        for kind, value, source in matchers:
            if kind not in ("geosite", "geoip"):
                continue
            f = ruleset_file(kind, value, source)
            if f in seen:
                continue
            seen.add(f)
            out.append((f, [SOURCES[s][kind].format(value) for s in ((source,) if source else SOURCE_ORDER)]))
    return out


def compose_routing(cfg, routing, rules_dir):
    final, rules = rules_of(routing)
    route = cfg.setdefault("route", {})
    sets = route.setdefault("rule_set", [])
    rrules = route.setdefault("rules", [])
    dns = cfg.setdefault("dns", {})
    drules = dns.setdefault("rules", [])
    proxy = next((o["tag"] for o in cfg.get("outbounds", []) if o.get("type") == "selector"), "proxy")
    target = {"proxy": {"outbound": proxy}, "direct": {"outbound": "direct"}, "block": {"action": "reject"}}
    dns_target = {"proxy": {"server": "dns-remote"}, "direct": {"server": "dns-direct"},
                  "block": {"action": "reject"}}

    rrules.append({"ip_is_private": True, "outbound": "direct"})
    files = set()
    gen_dns = []
    for i, (action, matchers) in enumerate(rules):
        fields, dfields, tags, dtags, protocols = {}, {}, [], [], []
        for kind, value, source in matchers:
            if kind == "protocol":
                protocols.append(value)
            elif kind in ("geosite", "geoip"):
                f = ruleset_file(kind, value, source)
                tag = PREFIX + f[:-4]
                if f not in files:
                    path = os.path.join(rules_dir, f)
                    if not os.path.exists(path):
                        raise Bad("%s:%s is not downloaded" % (kind, value))
                    files.add(f)
                    sets.append({"type": "local", "tag": tag, "format": "binary", "path": path})
                tags.append(tag)
                if kind == "geosite":
                    dtags.append(tag)
            else:
                field = FIELDS[kind]
                fields.setdefault(field, []).append(value)
                if field in DNS_FIELDS:
                    dfields.setdefault(field, []).append(value)
        if fields:
            tag = "%sr%d" % (PREFIX, i + 1)
            sets.append({"type": "inline", "tag": tag, "rules": [{k: v} for k, v in fields.items()]})
            tags.insert(0, tag)
        if dfields:
            tag = "%sd%d" % (PREFIX, i + 1)
            sets.append({"type": "inline", "tag": tag, "rules": [{k: v} for k, v in dfields.items()]})
            dtags.insert(0, tag)
        if tags:
            rrules.append(dict({"rule_set": tags}, **target[action]))
        if protocols:
            rrules.append(dict({"protocol": protocols}, **target[action]))
        if dtags:
            gen_dns.append(dict({"rule_set": dtags}, **dns_target[action]))

    route["final"] = proxy if final == "proxy" else "direct"
    # Before the catch-all (sub_parser's last DNS rule, no matcher fields).
    catch = len(drules)
    if drules and set(drules[-1]) <= {"action", "server", "strategy"}:
        catch = len(drules) - 1
        # Unmatched names resolve where their traffic goes.
        drules[-1]["server"] = "dns-remote" if final == "proxy" else "dns-direct"
    drules[catch:catch] = gen_dns
    if not sets:
        route.pop("rule_set")


def install_rules(routing, src, dst, uid):
    """Root: copy the .srs files `routing` needs from user `uid`'s download
    dir `src` to `dst`. `src` and its files are opened without following a
    final symlink and must be owned by `uid` (a password-free caller picks
    `src`: no root-only file may come out of it). A file that fails the
    checks is skipped: an older copy in `dst` stays, compose reports a
    missing one. Nothing is dropped here: a rollback to the previous config
    still needs its rule-sets (prune_rules, once the new one is up)."""
    need = [f for f, _ in rulesets(routing)]
    os.makedirs(dst, mode=0o755, exist_ok=True)
    dfd = None
    if src and uid >= 0:
        try:
            dfd = os.open(src, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            if os.fstat(dfd).st_uid != uid:
                os.close(dfd)
                dfd = None
        except OSError:
            dfd = None
    for f in need:
        if dfd is None:
            break
        try:
            fd = os.open(f, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dfd)
        except OSError:
            continue
        with os.fdopen(fd, "rb") as src_f:
            st = os.fstat(src_f.fileno())
            if not (stat.S_ISREG(st.st_mode) and st.st_uid == uid and st.st_size < 64 << 20):
                continue
            data = src_f.read()
        if not data.startswith(b"SRS"):
            continue
        tmp = os.path.join(dst, "." + f + ".tmp")
        with open(tmp, "wb") as out:
            out.write(data)
        os.chmod(tmp, 0o644)
        os.replace(tmp, os.path.join(dst, f))
    if dfd is not None:
        os.close(dfd)


def prune_rules(routing, dst):
    """Root: drop the .srs files in `dst` that `routing` does not need."""
    need = [f for f, _ in rulesets(routing)]
    if not os.path.isdir(dst):
        return
    for f in os.listdir(dst):
        if f.endswith(".srs") and f not in need:
            os.remove(os.path.join(dst, f))


TAGGED = {("outbounds",), ("endpoints",), ("inbounds",), ("dns", "servers"), ("route", "rule_set")}
PREPEND = {("route", "rules"), ("dns", "rules")}


def merge(base, over, path=()):
    for k, v in over.items():
        p = path + (k,)
        if v is None:
            base.pop(k, None)
        elif isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v, p)
        elif isinstance(v, list) and isinstance(base.get(k), list) and p in TAGGED:
            by_tag = {o.get("tag"): j for j, o in enumerate(base[k]) if isinstance(o, dict)}
            for o in v:
                j = by_tag.get(o.get("tag")) if isinstance(o, dict) else None
                if j is None:
                    base[k].append(o)
                else:
                    base[k][j] = o
        elif isinstance(v, list) and isinstance(base.get(k), list) and p in PREPEND:
            # After the leading sniff / hijack-dns rules (theirs see the
            # sniffed domain) and Xray's own uid rule (no loop through the
            # TUN); DNS has no such rules (index 0).
            n = 0
            while n < len(base[k]) and (base[k][n].get("action") in ("sniff", "hijack-dns")
                                        or "user_id" in base[k][n]):
                n += 1
            base[k][n:n] = v
        else:
            base[k] = v


def check_refs(cfg):
    """`sing-box check` parses only: a dangling tag fails at start, with the
    VPN down. The references routing / an overlay can break."""
    outs = {o.get("tag") for k in ("outbounds", "endpoints") for o in cfg.get(k, []) if isinstance(o, dict)}
    dns = cfg.get("dns") or {}
    route = cfg.get("route") or {}
    servers = {s.get("tag") for s in dns.get("servers", []) if isinstance(s, dict)}
    sets = {s.get("tag") for s in route.get("rule_set", []) if isinstance(s, dict)}
    bad = []

    def need(kind, have, tag, where):
        if tag is not None and tag not in have:
            bad.append("%s: unknown %s %r" % (where, kind, tag))

    def resolver(r, where):
        need("DNS server", servers, r.get("server") if isinstance(r, dict) else r, where)

    def rules(lst, where, field, have, kind):
        for i, r in enumerate(lst or []):
            if not isinstance(r, dict):
                continue
            w = "%s[%d]" % (where, i)
            need(kind, have, r.get(field), w)
            rs = r.get("rule_set")
            for t in [rs] if isinstance(rs, str) else rs or []:
                need("rule-set", sets, t, w)
            rules(r.get("rules"), w, field, have, kind)  # logical rules

    need("outbound", outs, route.get("final"), "route.final")
    rules(route.get("rules"), "route.rules", "outbound", outs, "outbound")
    rules(dns.get("rules"), "dns.rules", "server", servers, "DNS server")
    need("DNS server", servers, dns.get("final"), "dns.final")
    if route.get("default_domain_resolver") is not None:
        resolver(route["default_domain_resolver"], "route.default_domain_resolver")
    for k in ("outbounds", "endpoints"):
        for o in cfg.get(k, []):
            if not isinstance(o, dict):
                continue
            w = "%s %r" % (k[:-1], o.get("tag"))
            for t in o.get("outbounds") or []:
                need("outbound", outs, t, w)
            need("outbound", outs, o.get("detour"), w)
            if o.get("domain_resolver") is not None:
                resolver(o["domain_resolver"], w)
    for s in dns.get("servers", []):
        if isinstance(s, dict):
            w = "dns server %r" % s.get("tag")
            need("outbound", outs, s.get("detour"), w)
            if s.get("domain_resolver") is not None:
                resolver(s["domain_resolver"], w)
    if bad:
        raise Bad("; ".join(bad[:3]) + (" (+%d more)" % (len(bad) - 3) if len(bad) > 3 else ""))


def main():
    a = sys.argv[1:]
    try:
        if a[:1] == ["check"] and len(a) >= 2:
            rules_of(load(a[1], {}))
            over = load(a[2] if len(a) > 2 else "", {})
            if not isinstance(over, dict):
                raise Bad("overlay: not an object")
        elif a[:1] == ["rulesets"] and len(a) == 2:
            for f, urls in rulesets(load(a[1], {})):
                print("\t".join([f] + urls))
        elif a[:1] == ["install-rules"] and len(a) == 5:
            install_rules(load(a[1], {}), a[2], a[3], int(a[4]) if a[4].lstrip("-").isdigit() else -1)
        elif a[:1] == ["prune-rules"] and len(a) == 3:
            prune_rules(load(a[1], {}), a[2])
        elif a[:1] == ["compose"] and len(a) == 6:
            cfg = load(a[1], None)
            if not isinstance(cfg, dict):
                raise Bad("no base config")
            compose_routing(cfg, load(a[2], {}), a[4])
            over = load(a[3], {})
            if not isinstance(over, dict):
                raise Bad("overlay: not an object")
            merge(cfg, over)
            check_refs(cfg)
            with open(a[5], "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2, ensure_ascii=False)
        else:
            sys.stderr.write("usage: see the header\n")
            sys.exit(2)
    except Bad as e:
        print("ERR:%s" % e)
        sys.exit(1)


if __name__ == "__main__":
    main()
