#!/usr/bin/env python3
# Moves the nodes sing-box cannot carry to Xray (scripts/vpn/vpn.sh _apply).
#
# sing-box stays the TUN / routing / DNS engine. Its gRPC transport is the
# "lite" one unless built with_grpc (Arch's is not), which Xray servers
# reject; XHTTP and VLESS Encryption it has no support for at all. Each such
# node becomes an
# Xray outbound behind its own local shadowsocks-2022 inbound (127.0.0.1,
# a random free port), and the sing-box outbound of the same tag a
# `shadowsocks` client to it — the selector, the node list and switching do
# not change. Xray's own uplink
# connections must not enter the TUN again: its uid is excluded from the
# TUN routes (tun.exclude_uid) and, should one still get in, routed direct
# (route rule `user`). The local hops are keyed (a fresh random key per node
# each run): other local programs cannot ride the tunnel through them. Not
# SOCKS: its password covers TCP only, UDP ASSOCIATE datagrams carry no auth;
# shadowsocks-2022 authenticates every packet, UDP included.
#
# gRPC nodes Xray cannot take stay sing-box's (its lite gRPC still reaches
# non-Xray servers). XHTTP / VLESS Encryption nodes cannot stay: one that
# Xray cannot take either (a transport it lacks, e.g. h2) is dropped, and
# without Xray (`--drop`) all of them are — sing-box would reject the whole
# config over one of them. Each dropped node: a "SKIPPED:tag<TAB>why" line
# on stdout (the panel counts them).
#
# Argv: <sing-box config (rewritten in place)> <xray config out>
#       <nodes out: "tag<TAB>type<TAB>flags" per moved node> <xray uid>
#       [extras (sub_parser.py's Xray-only link parameters)]
#   or: --drop <sing-box config (rewritten in place)> [extras]
# flags: "insecure" = the link asked to skip the certificate check, which
# Xray no longer can (allowInsecure was removed in 2026-06): it verifies.
# Exit 0 = written (no moved node → empty nodes file, no Xray config);
# 1 = bad input; 2 = no node left in a selector.

import base64
import json
import secrets
import socket
import sys

XRAY_PROTOCOLS = ("vless", "vmess", "trojan")
SS_METHOD = "2022-blake3-aes-128-gcm"  # key = 16 random bytes, base64
PORT_RANGE = (20000, 60000)


def warn(msg):
    sys.stderr.write("xray_split: %s\n" % msg)


def free_port(taken):
    """A random port in PORT_RANGE free on 127.0.0.1 for both TCP and UDP."""
    for _ in range(200):
        port = PORT_RANGE[0] + secrets.randbelow(PORT_RANGE[1] - PORT_RANGE[0])
        if port in taken:
            continue
        try:
            for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
                with socket.socket(socket.AF_INET, kind) as s:
                    s.bind(("127.0.0.1", port))
        except OSError:
            continue
        taken.add(port)
        return port
    raise OSError("no free local port")


def needs_xray(ob, extra):
    """sing-box has no support for it at all: XHTTP, VLESS Encryption."""
    if ob.get("type") not in XRAY_PROTOCOLS:
        return False
    return ((ob.get("transport") or {}).get("type") == "xhttp"
            or ob.get("type") == "vless" and "encryption" in extra)


def wants_xray(ob, extra):
    """needs_xray, or gRPC (sing-box's lite one fails against Xray servers)."""
    return needs_xray(ob, extra) or (
        ob.get("type") in XRAY_PROTOCOLS
        and (ob.get("transport") or {}).get("type") == "grpc")


def with_early_data(path, tr):
    # sing-box's max_early_data in the Sec-WebSocket-Protocol header = Xray's
    # `ed` path parameter (the other, in-path early data Xray has not).
    ed = tr.get("max_early_data")
    if not ed or tr.get("early_data_header_name") != "Sec-WebSocket-Protocol":
        return path
    return "%s%sed=%d" % (path, "&" if "?" in path else "?", ed)


def http_headers(tr, host_key):
    """sing-box's Host (headers.Host or `host`) and the other headers."""
    headers = dict(tr.get("headers") or {})
    host = tr.get(host_key) or headers.pop("Host", "") or headers.pop("host", "")
    if isinstance(host, list):
        host = host[0] if host else ""
    headers = {k: (v[0] if isinstance(v, list) else v) for k, v in headers.items() if v}
    return host, headers


def stream(ob, extra):
    tr = ob.get("transport") or {}
    tls = ob.get("tls") or {}
    net = tr.get("type", "raw")
    s = {"network": net}
    if net == "raw":
        pass
    elif net == "grpc":
        g = {"serviceName": tr.get("service_name", "")}
        if extra.get("authority"):
            g["authority"] = extra["authority"]
        if extra.get("multiMode"):
            g["multiMode"] = True
        s["grpcSettings"] = g
    elif net in ("ws", "httpupgrade"):
        host, headers = http_headers(tr, "host")
        w = {"path": with_early_data(tr.get("path") or "/", tr)}
        if host:
            w["host"] = host
        if headers:
            w["headers"] = headers
        s["wsSettings" if net == "ws" else "httpupgradeSettings"] = w
    elif net != "xhttp":
        # sing-box's http (h2) / quic: Xray removed the one, never had the other.
        raise ValueError("Xray has no %s transport" % net)
    else:
        x = {}
        if tr.get("path"):
            x["path"] = tr["path"]
        host = tr.get("host")
        if host:
            x["host"] = host[0] if isinstance(host, list) else host
        if tr.get("mode"):
            x["mode"] = tr["mode"]
        if extra.get("xhttpExtra"):
            x["extra"] = extra["xhttpExtra"]
        s["xhttpSettings"] = x
    if not tls.get("enabled"):
        s["security"] = "none"
        return s
    fp = (tls.get("utls") or {}).get("fingerprint", "")
    reality = tls.get("reality") or {}
    if reality.get("enabled"):
        s["security"] = "reality"
        r = {
            "serverName": tls.get("server_name", ""),
            "fingerprint": fp or "chrome",
            "publicKey": reality.get("public_key", ""),
            "shortId": reality.get("short_id", ""),
        }
        if extra.get("spiderX"):
            r["spiderX"] = extra["spiderX"]
        s["realitySettings"] = r
        return s
    s["security"] = "tls"
    t = {}
    if tls.get("server_name"):
        t["serverName"] = tls["server_name"]
    if tls.get("alpn"):
        t["alpn"] = tls["alpn"]
    if fp:
        t["fingerprint"] = fp
    if tls.get("insecure"):
        # Xray removed allowInsecure (2026-06): the node verifies the cert.
        warn("%s: insecure TLS is not supported by Xray, verifying" % ob["tag"])
    s["tlsSettings"] = t
    return s


def outbound(ob, tag, extra):
    t = ob["type"]
    addr, port = ob["server"], ob["server_port"]
    if t == "vless":
        settings = {"address": addr, "port": port, "id": ob["uuid"],
                    "encryption": extra.get("encryption", "none")}
        flow = ob.get("flow") or extra.get("flow")
        if flow:
            settings["flow"] = flow
    elif t == "vmess":
        settings = {"address": addr, "port": port, "id": ob["uuid"],
                    "security": ob.get("security", "auto")}
    else:
        settings = {"address": addr, "port": port, "password": ob["password"]}
    return {"tag": tag, "protocol": t, "settings": settings, "streamSettings": stream(ob, extra)}


def drop(cfg, dropped):
    """Removes the outbounds {tag: why} and every reference to them from the
    groups. Exits 2 when a group is left with no node."""
    if not dropped:
        return
    cfg["outbounds"] = [o for o in cfg.get("outbounds", []) if o.get("tag") not in dropped]
    for o in cfg["outbounds"]:
        if o.get("type") not in ("selector", "urltest") or "outbounds" not in o:
            continue
        o["outbounds"] = [t for t in o["outbounds"] if t not in dropped]
        if not o["outbounds"]:
            warn("%s: no node left" % o.get("tag"))
            sys.exit(2)
        if o.get("default") in dropped:
            o["default"] = o["outbounds"][0]
    for tag, why in dropped.items():
        warn("%s: %s, skipped" % (tag, why))
        print("SKIPPED:%s\t%s" % (tag, why))


def drop_only():
    """--drop: no Xray here — the nodes that need it go."""
    if len(sys.argv) < 3:
        sys.exit(1)
    sb_path = sys.argv[2]
    try:
        with open(sb_path, encoding="utf-8") as f:
            cfg = json.load(f)
        extras = {}
        if len(sys.argv) > 3:
            with open(sys.argv[3], encoding="utf-8") as f:
                extras = json.load(f)
    except Exception as e:
        warn(str(e))
        sys.exit(1)
    drop(cfg, {ob["tag"]: "needs Xray (not installed)" for ob in cfg.get("outbounds", [])
               if needs_xray(ob, extras.get(ob.get("tag"), {}))})
    with open(sb_path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--drop":
        drop_only()
        return
    if len(sys.argv) < 5:
        sys.exit(1)
    sb_path, xray_path, nodes_path, uid = sys.argv[1:5]
    extras_path = sys.argv[5] if len(sys.argv) > 5 else ""
    try:
        with open(sb_path, encoding="utf-8") as f:
            cfg = json.load(f)
        uid = int(uid)
        extras = {}
        if extras_path:
            with open(extras_path, encoding="utf-8") as f:
                extras = json.load(f)
    except Exception as e:
        warn(str(e))
        sys.exit(1)

    inbounds, outbounds, rules, nodes = [], [], [], []
    ports = set()
    dropped = {}
    for ob in cfg.get("outbounds", []):
        extra = extras.get(ob.get("tag"), {})
        if not wants_xray(ob, extra):
            continue
        i = len(nodes)
        try:
            outbounds.append(outbound(ob, "out-%d" % i, extra))
        except (KeyError, ValueError) as e:
            why = "missing %s" % e if isinstance(e, KeyError) else str(e)
            if needs_xray(ob, extra):
                dropped[ob.get("tag")] = why
            else:
                warn("%s: %s, left to sing-box" % (ob.get("tag"), why))
            continue
        try:
            port = free_port(ports)
        except OSError as e:
            warn(str(e))
            sys.exit(1)
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        inbounds.append({"tag": "in-%d" % i, "listen": "127.0.0.1", "port": port,
                         "protocol": "shadowsocks",
                         "settings": {"method": SS_METHOD, "password": key,
                                      "network": "tcp,udp"}})
        rules.append({"inboundTag": ["in-%d" % i], "outboundTag": "out-%d" % i})
        insecure = bool((ob.get("tls") or {}).get("insecure"))
        nodes.append((ob["tag"], ob["type"], "insecure" if insecure else ""))
        tag = ob["tag"]
        ob.clear()
        ob.update({"type": "shadowsocks", "tag": tag, "server": "127.0.0.1",
                   "server_port": port, "method": SS_METHOD, "password": key})

    drop(cfg, dropped)
    if nodes:
        for inb in cfg.get("inbounds", []):
            if inb.get("type") == "tun":
                inb["exclude_uid"] = sorted(set(inb.get("exclude_uid", []) + [uid]))
        route = cfg.setdefault("route", {})
        # After the sniff / hijack-dns rules, before anything else routes.
        route.setdefault("rules", []).append({"user_id": [uid], "outbound": "direct"})
        xray = {
            "log": {"loglevel": "warning"},
            "inbounds": inbounds,
            "outbounds": outbounds + [{"tag": "block", "protocol": "blackhole"}],
            "routing": {"rules": rules},
        }
        with open(xray_path, "w", encoding="utf-8") as f:
            json.dump(xray, f, indent=2, ensure_ascii=False)

    with open(sb_path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    with open(nodes_path, "w", encoding="utf-8") as f:
        for tag, t, flags in nodes:
            f.write("%s\t%s\t%s\n" % (tag, t, flags))
    sys.stderr.write("xray_split: %d node(s) to Xray\n" % len(nodes))


if __name__ == "__main__":
    main()
