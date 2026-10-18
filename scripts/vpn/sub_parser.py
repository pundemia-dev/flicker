#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Replicates Throne's Subscription::RawUpdater dispatch/parse behaviour and
# emits a sing-box >= 1.12 (target 1.13.12) configuration.
#
# Argv: <config_path> <raw_subscription_file>
# Exit 0 on success (config written), 1 on failure (no nodes / read error).

import sys
import re
import json
import base64
import urllib.parse

# ---------------------------------------------------------------------------
# Collected nodes
# ---------------------------------------------------------------------------
OUTBOUNDS = []     # proxy outbounds (everything except wireguard)
ENDPOINTS = []     # wireguard endpoints (sing-box >= 1.11)
ORDER_TAGS = []    # tags in subscription order (proxies + endpoints mixed)
_USED_TAGS = set()

UTLS_FP = {
    "chrome", "firefox", "safari", "edge", "ios", "android",
    "random", "randomized", "360", "qq",
}


def _uniq_tag(tag):
    tag = (tag or "").strip()
    if not tag:
        tag = "proxy"
    base = tag
    i = 1
    while tag in _USED_TAGS:
        tag = "%s %d" % (base, i)
        i += 1
    _USED_TAGS.add(tag)
    return tag


def add_outbound(ob):
    if not isinstance(ob, dict):
        return

    ob["tag"] = _uniq_tag(ob.get("tag"))
    OUTBOUNDS.append(ob)
    ORDER_TAGS.append(ob["tag"])


def add_endpoint(ep):
    if not isinstance(ep, dict):
        return
    ep["tag"] = _uniq_tag(ep.get("tag"))
    ENDPOINTS.append(ep)
    ORDER_TAGS.append(ep["tag"])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def b64_decode_loose(s):
    s = (s or "").strip().replace("\n", "").replace("\r", "")
    s = s.replace("-", "+").replace("_", "/")
    s += "=" * (-len(s) % 4)
    return base64.b64decode(s)


def try_b64_text(s):
    """Throne's DecodeB64IfValid + v2rayNG-style binary guard: only treat as
    base64 when it both looks like base64 and decodes to something that
    resembles subscription content."""
    s2 = (s or "").strip()
    if len(s2) < 8:
        return None
    if not re.fullmatch(r"[A-Za-z0-9+/_\-=\s]+", s2):
        return None
    try:
        txt = b64_decode_loose(s2).decode("utf-8")
    except Exception:
        return None
    if not txt or not txt.strip():
        return None
    # Some subscription endpoints serve base64-encoded compressed blobs that
    # decode to mostly-binary garbage. Reject them before they get dispatched.
    printable = sum(1 for c in txt if c.isprintable() or c in "\n\r\t")
    if printable / max(len(txt), 1) < 0.9:
        return None
    if ("://" in txt) or ("{" in txt) or ("proxies:" in txt):
        return txt
    return None


def query_dict(query):
    out = {}
    for k, v in urllib.parse.parse_qs(query, keep_blank_values=True).items():
        out[k.lower()] = urllib.parse.unquote(v[0]) if v else ""
    return out


def as_bool(v):
    return str(v).strip().lower() in ("1", "true", "yes")


def split_alpn(v):
    if not v:
        return None
    parts = [p for p in re.split(r"[,\s]+", v) if p]
    return parts or None


def build_tls(security, sni="", fp="", alpn="", pbk="", sid="",
              insecure=False, host=""):
    security = (security or "").lower()
    server_name = sni or host
    if security not in ("tls", "reality", "xtls") and not server_name \
            and not pbk and not insecure:
        return None
    tls = {"enabled": True}
    if server_name:
        tls["server_name"] = server_name
    if insecure:
        tls["insecure"] = True
    alpn_list = split_alpn(alpn)
    if alpn_list:
        tls["alpn"] = alpn_list
    if fp:
        tls["utls"] = {
            "enabled": True,
            "fingerprint": fp if fp in UTLS_FP else "chrome",
        }
    if security == "reality":
        reality = {"enabled": True}
        if pbk:
            reality["public_key"] = pbk
        reality["short_id"] = sid or ""
        tls["reality"] = reality
        if "utls" not in tls:  # REALITY requires uTLS
            tls["utls"] = {"enabled": True, "fingerprint": "chrome"}
    return tls


def build_transport(net, q, host_header=""):
    net = (net or "tcp").lower()
    path = q.get("path", "") or "/"
    host = host_header or q.get("host", "")
    if net in ("ws", "websocket"):
        t = {"type": "websocket", "path": path}
        if host:
            t["headers"] = {"Host": host}
        ed = q.get("ed") or q.get("eh")
        try:
            if q.get("ed"):
                t["max_early_data"] = int(q.get("ed"))
                t["early_data_header_name"] = "Sec-WebSocket-Protocol"
        except Exception:
            pass
        return t
    if net == "grpc":
        return {"type": "grpc",
                "service_name": q.get("servicename") or q.get("path", "")}
    if net == "httpupgrade":
        t = {"type": "httpupgrade", "path": path}
        if host:
            t["host"] = host
        return t
    if net in ("xhttp", "splithttp"):
        # XHTTP (xray-core names it `splithttp`, v2rayNG emits it the same way)
        # is a sing-box 1.11+ transport that splits traffic over plain HTTP/1.1
        # to defeat pattern-based DPI. Query keys follow the xray spec:
        #   path, host, mode (auto | packet-up | stream-up | stream-one).
        t = {"type": "xhttp"}
        if path and path != "/":
            t["path"] = path
        if host:
            t["host"] = [h for h in host.split(",") if h]
        mode = q.get("mode", "")
        if mode in ("auto", "packet-up", "stream-up", "stream-one"):
            t["mode"] = mode
        return t
    if net in ("h2", "http"):
        t = {"type": "http"}
        if path and path != "/":
            t["path"] = path
        if host:
            t["host"] = [h for h in host.split(",") if h]
        return t
    return None  # tcp / raw => no transport


# ---------------------------------------------------------------------------
# Individual share-link parsers
# ---------------------------------------------------------------------------
def parse_vless(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 443)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "vless", "tag": tag, "server": host, "server_port": port,
        "uuid": urllib.parse.unquote(u.username or ""),
        "packet_encoding": q.get("packetencoding", "xudp"),
    }
    net = q.get("type", "tcp").lower()
    flow = q.get("flow", "")
    if flow and net in ("tcp", "raw", ""):
        ob["flow"] = flow
    sec = q.get("security", "").lower()
    if sec in ("tls", "reality", "xtls"):
        ob["tls"] = build_tls(
            "reality" if sec == "reality" else "tls",
            q.get("sni", ""), q.get("fp", ""), q.get("alpn", ""),
            q.get("pbk", ""), q.get("sid", ""),
            as_bool(q.get("allowinsecure", q.get("insecure", "0"))),
            q.get("host", ""))
    tr = build_transport(net, q)
    if tr:
        ob["transport"] = tr
    add_outbound(ob)


def parse_vmess(line):
    body = line[len("vmess://"):]
    txt = None
    try:
        txt = b64_decode_loose(body).decode("utf-8")
    except Exception:
        txt = None
    if not txt or not txt.lstrip().startswith("{"):
        return
    d = json.loads(txt)
    host = d.get("add", "")
    ob = {
        "type": "vmess", "tag": d.get("ps") or host, "server": host,
        "server_port": int(d.get("port", 443) or 443),
        "uuid": d.get("id", ""),
        "security": d.get("scy") or "auto",
        "alter_id": int(d.get("aid", 0) or 0),
        "packet_encoding": "xudp",
    }
    net = str(d.get("net", "tcp")).lower()
    tls_field = str(d.get("tls", "")).lower()
    if tls_field in ("tls", "reality"):
        ob["tls"] = build_tls(tls_field, d.get("sni") or d.get("host", ""),
                              d.get("fp", ""), d.get("alpn", ""),
                              host=d.get("host", ""))
    host_hdr = d.get("host", "")
    tr = build_transport(
        net,
        {"path": d.get("path", "/"), "host": host_hdr,
         "servicename": d.get("path", "")},
        host_hdr)
    if tr:
        ob["transport"] = tr
    add_outbound(ob)


def parse_trojan(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 443)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "trojan", "tag": tag, "server": host, "server_port": port,
        "password": urllib.parse.unquote(u.username or ""),
    }
    sec = q.get("security", "tls").lower()
    if sec in ("tls", "reality", "xtls"):
        ob["tls"] = build_tls(
            "reality" if sec == "reality" else "tls",
            q.get("sni", ""), q.get("fp", ""), q.get("alpn", ""),
            q.get("pbk", ""), q.get("sid", ""),
            as_bool(q.get("allowinsecure", q.get("insecure", "0"))),
            q.get("host", ""))
    tr = build_transport(q.get("type", "tcp").lower(), q)
    if tr:
        ob["transport"] = tr
    add_outbound(ob)


def parse_hysteria2(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 443)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "hysteria2", "tag": tag, "server": host, "server_port": port,
        "password": urllib.parse.unquote(u.username or ""),
    }
    obfs = q.get("obfs", "")
    if obfs:
        ob["obfs"] = {"type": obfs,
                      "password": q.get("obfs-password", q.get("obfspassword", ""))}
    tls = {"enabled": True, "server_name": q.get("sni", host)}
    if as_bool(q.get("insecure", "0")):
        tls["insecure"] = True
    alpn = split_alpn(q.get("alpn", ""))
    if alpn:
        tls["alpn"] = alpn
    ob["tls"] = tls
    add_outbound(ob)


def parse_hysteria1(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 443)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "hysteria", "tag": tag, "server": host, "server_port": port,
    }
    auth = q.get("auth", q.get("auth_str", q.get("authstr", "")))
    if auth:
        ob["auth_str"] = auth
    try:
        if q.get("upmbps"):
            ob["up_mbps"] = int(q.get("upmbps"))
        if q.get("downmbps"):
            ob["down_mbps"] = int(q.get("downmbps"))
    except Exception:
        pass
    obfs = q.get("obfs", q.get("obfsparam", ""))
    if obfs:
        ob["obfs"] = obfs
    tls = {"enabled": True,
           "server_name": q.get("peer", q.get("sni", host))}
    if as_bool(q.get("insecure", "0")):
        tls["insecure"] = True
    alpn = split_alpn(q.get("alpn", ""))
    if alpn:
        tls["alpn"] = alpn
    ob["tls"] = tls
    add_outbound(ob)


def parse_tuic(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 443)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "tuic", "tag": tag, "server": host, "server_port": port,
        "uuid": urllib.parse.unquote(u.username or ""),
        "password": urllib.parse.unquote(u.password or ""),
    }
    cc = q.get("congestion_control", q.get("congestion-controller", ""))
    if cc:
        ob["congestion_control"] = cc
    urm = q.get("udp_relay_mode", q.get("udp-relay-mode", ""))
    if urm:
        ob["udp_relay_mode"] = urm
    tls = {"enabled": True, "server_name": q.get("sni", host)}
    if as_bool(q.get("allow_insecure", q.get("insecure", "0"))):
        tls["insecure"] = True
    alpn = split_alpn(q.get("alpn", ""))
    if alpn:
        tls["alpn"] = alpn
    ob["tls"] = tls
    add_outbound(ob)


def parse_anytls(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 443)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    password = urllib.parse.unquote(u.password or u.username or "")
    ob = {
        "type": "anytls", "tag": tag, "server": host, "server_port": port,
        "password": password,
    }
    tls = {"enabled": True, "server_name": q.get("sni", host)}
    if as_bool(q.get("insecure", q.get("allowinsecure", "0"))):
        tls["insecure"] = True
    alpn = split_alpn(q.get("alpn", ""))
    if alpn:
        tls["alpn"] = alpn
    ob["tls"] = tls
    add_outbound(ob)


def parse_shadowsocks(line):
    rest = line[len("ss://"):]
    frag = ""
    if "#" in rest:
        rest, frag = rest.split("#", 1)
    tag = urllib.parse.unquote(frag) if frag else ""
    query = ""
    if "?" in rest:
        rest, query = rest.split("?", 1)
    q = query_dict(query)

    method = password = host = ""
    port = 0
    if "@" in rest:
        userinfo, server = rest.rsplit("@", 1)
        # userinfo may be base64(method:password) or plain method:password
        creds = None
        try:
            dec = b64_decode_loose(userinfo).decode("utf-8")
            if ":" in dec:
                creds = dec
        except Exception:
            creds = None
        if creds is None:
            creds = urllib.parse.unquote(userinfo)
        if ":" in creds:
            method, password = creds.split(":", 1)
        host, _, p = server.partition(":")
        port = int(p or 0)
    else:
        # legacy: whole thing base64(method:password@host:port)
        try:
            dec = b64_decode_loose(rest).decode("utf-8")
        except Exception:
            return
        if "@" not in dec or ":" not in dec:
            return
        creds, server = dec.rsplit("@", 1)
        method, password = creds.split(":", 1)
        host, _, p = server.partition(":")
        port = int(p or 0)

    if not host or not port:
        return
    ob = {
        "type": "shadowsocks", "tag": tag or host, "server": host,
        "server_port": port, "method": method, "password": password,
    }
    plugin = q.get("plugin", "")
    if plugin:
        # plugin string is "name;opt1=val;opt2"
        if ";" in plugin:
            name, opts = plugin.split(";", 1)
        else:
            name, opts = plugin, ""
        ob["plugin"] = name
        if opts:
            ob["plugin_opts"] = opts
    add_outbound(ob)


def parse_socks(line):
    u = urllib.parse.urlparse(line)
    host = u.hostname or ""
    port = int(u.port or 1080)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "socks", "tag": tag, "server": host, "server_port": port,
        "version": "5",
    }
    if u.username:
        ob["username"] = urllib.parse.unquote(u.username)
    if u.password:
        ob["password"] = urllib.parse.unquote(u.password)
    if u.scheme in ("socks4", "socks4a"):
        ob["version"] = "4"
    add_outbound(ob)


def parse_http(line):
    u = urllib.parse.urlparse(line)
    host = u.hostname or ""
    port = int(u.port or (443 if u.scheme == "https" else 80))
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "http", "tag": tag, "server": host, "server_port": port,
    }
    if u.username:
        ob["username"] = urllib.parse.unquote(u.username)
    if u.password:
        ob["password"] = urllib.parse.unquote(u.password)
    if u.scheme == "https":
        ob["tls"] = {"enabled": True, "server_name": host}
    add_outbound(ob)


def parse_ssh(line):
    u = urllib.parse.urlparse(line)
    host = u.hostname or ""
    port = int(u.port or 22)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    ob = {
        "type": "ssh", "tag": tag, "server": host, "server_port": port,
    }
    if u.username:
        ob["user"] = urllib.parse.unquote(u.username)
    if u.password:
        ob["password"] = urllib.parse.unquote(u.password)
    add_outbound(ob)


def parse_wg_link(line):
    u = urllib.parse.urlparse(line)
    q = query_dict(u.query)
    host = u.hostname or ""
    port = int(u.port or 51820)
    tag = urllib.parse.unquote(u.fragment) if u.fragment else host
    priv = (urllib.parse.unquote(u.username) if u.username
            else q.get("privatekey", q.get("private_key", q.get("secretkey", ""))))
    pub = q.get("publickey", q.get("public_key", q.get("peer", q.get("peerpublickey", ""))))
    addr = q.get("address", q.get("ip", ""))
    addresses = [a for a in re.split(r"[,\s]+", addr) if a] or ["172.16.0.2/32"]
    peer = {
        "address": host, "port": port, "public_key": pub,
        "allowed_ips": ["0.0.0.0/0", "::/0"],
    }
    psk = q.get("presharedkey", q.get("pre_shared_key", q.get("psk", "")))
    if psk:
        peer["pre_shared_key"] = psk
    reserved = q.get("reserved", "")
    if reserved:
        try:
            peer["reserved"] = [int(x) for x in re.split(r"[,\s]+", reserved) if x != ""]
        except Exception:
            pass
    ep = {
        "type": "wireguard", "tag": tag, "address": addresses,
        "private_key": priv, "peers": [peer],
    }
    if q.get("mtu"):
        try:
            ep["mtu"] = int(q.get("mtu", 1500))
        except Exception:
            ep["mtu"] = 1500
    add_endpoint(ep)


def parse_json_link(line):
    """json://<base64url(json)>  (Throne 'json link' format)."""
    u = urllib.parse.urlparse(line)
    frag = u.fragment or (line[len("json://"):])
    try:
        data = json.loads(b64_decode_loose(frag).decode("utf-8"))
    except Exception:
        return
    if isinstance(data, dict):
        parse_singbox_node(data)


SHARE_PREFIXES = (
    ("vless://", parse_vless),
    ("vmess://", parse_vmess),
    ("trojan://", parse_trojan),
    ("hysteria2://", parse_hysteria2),
    ("hy2://", parse_hysteria2),
    ("hysteria://", parse_hysteria1),
    ("tuic://", parse_tuic),
    ("anytls://", parse_anytls),
    ("ss://", parse_shadowsocks),
    ("socks5://", parse_socks),
    ("socks4a://", parse_socks),
    ("socks4://", parse_socks),
    ("socks://", parse_socks),
    ("https://", parse_http),
    ("http://", parse_http),
    ("ssh://", parse_ssh),
    ("wg://", parse_wg_link),
    ("wireguard://", parse_wg_link),
)


def parse_share_link(line):
    if line.startswith("json://"):
        parse_json_link(line)
        return
    for prefix, fn in SHARE_PREFIXES:
        if line.startswith(prefix):
            try:
                fn(line)
            except Exception:
                pass
            return


# ---------------------------------------------------------------------------
# sing-box JSON node ingestion (already in sing-box format)
# ---------------------------------------------------------------------------
VALID_NODE_TYPES = {
    "socks", "http", "shadowsocks", "vmess", "vless", "trojan",
    "anytls", "hysteria", "hysteria2", "tuic", "wireguard", "ssh",
    "shadowtls", "naive", "tor",
}


def _wg_outbound_to_endpoint(out):
    """Convert a legacy (<=1.10) WireGuard outbound to a 1.11+ endpoint."""
    ep = {"type": "wireguard", "tag": out.get("tag", "wireguard")}
    addr = out.get("local_address") or out.get("address") or []
    if isinstance(addr, str):
        addr = [addr]
    ep["address"] = addr
    if out.get("private_key"):
        ep["private_key"] = out["private_key"]
    if out.get("mtu"):
        ep["mtu"] = out["mtu"]
    if out.get("system_interface"):
        ep["system"] = True
    if out.get("interface_name"):
        ep["name"] = out["interface_name"]
    peer = {}
    if out.get("server"):
        peer["address"] = out["server"]
    if out.get("server_port"):
        peer["port"] = out["server_port"]
    if out.get("peer_public_key"):
        peer["public_key"] = out["peer_public_key"]
    if out.get("pre_shared_key"):
        peer["pre_shared_key"] = out["pre_shared_key"]
    peer["allowed_ips"] = ["0.0.0.0/0", "::/0"]
    if out.get("reserved"):
        peer["reserved"] = out["reserved"]
    ep["peers"] = [peer]
    return ep


def parse_singbox_node(out):
    if not isinstance(out, dict):
        return
    t = out.get("type")
    if t not in VALID_NODE_TYPES:
        return
    node = dict(out)
    # Drop dial fields that were removed/renamed and would taint a clean config.
    node.pop("domain_strategy", None)
    if t == "wireguard":
        # legacy outbound vs already-endpoint
        if "peers" in node or "address" in node and "server" not in node:
            node["type"] = "wireguard"
            add_endpoint(node)
        else:
            add_endpoint(_wg_outbound_to_endpoint(node))
        return
    add_outbound(node)


def update_singbox(j):
    for arr in ("outbounds", "endpoints"):
        for item in j.get(arr, []) or []:
            if isinstance(item, dict):
                parse_singbox_node(item)


def update_sip008(j):
    for srv in j.get("servers", []) or []:
        if not isinstance(srv, dict):
            continue
        host = srv.get("server", "")
        port = srv.get("server_port", 0)
        if not host or not port:
            continue
        ob = {
            "type": "shadowsocks",
            "tag": srv.get("remarks") or srv.get("name") or host,
            "server": host, "server_port": int(port),
            "method": srv.get("method", ""), "password": srv.get("password", ""),
        }
        if srv.get("plugin"):
            ob["plugin"] = srv["plugin"]
            if srv.get("plugin_opts"):
                ob["plugin_opts"] = srv["plugin_opts"]
        add_outbound(ob)


# ---------------------------------------------------------------------------
# Clash (best-effort, no remote conversion API available)
# ---------------------------------------------------------------------------
def _clash_node_to_singbox(p):
    if not isinstance(p, dict):
        return
    t = str(p.get("type", "")).lower()
    name = p.get("name") or p.get("server", "")
    server = p.get("server", "")
    port = int(p.get("port", 0) or 0)
    if not server or not port:
        return
    insecure = as_bool(p.get("skip-cert-verify", False))
    sni = p.get("sni") or p.get("servername") or ""
    net = str(p.get("network", "tcp")).lower()

    def ws_grpc(ob):
        if net == "ws":
            wsopts = p.get("ws-opts", {}) or {}
            path = wsopts.get("path", "/")
            host = ""
            hdr = wsopts.get("headers", {}) or {}
            for k, v in hdr.items():
                if k.lower() == "host":
                    host = v
            ob["transport"] = {"type": "websocket", "path": path}
            if host:
                ob["transport"]["headers"] = {"Host": host}
        elif net == "grpc":
            gopts = p.get("grpc-opts", {}) or {}
            ob["transport"] = {"type": "grpc",
                               "service_name": gopts.get("grpc-service-name", "")}

    if t == "ss":
        ob = {"type": "shadowsocks", "tag": name, "server": server,
              "server_port": port, "method": p.get("cipher", ""),
              "password": p.get("password", "")}
        if p.get("plugin"):
            ob["plugin"] = p["plugin"]
            popts = p.get("plugin-opts", {}) or {}
            if popts:
                ob["plugin_opts"] = ";".join("%s=%s" % (k, v) for k, v in popts.items())
        add_outbound(ob)
    elif t == "vmess":
        ob = {"type": "vmess", "tag": name, "server": server, "server_port": port,
              "uuid": p.get("uuid", ""), "alter_id": int(p.get("alterId", 0) or 0),
              "security": p.get("cipher", "auto"), "packet_encoding": "xudp"}
        if as_bool(p.get("tls", False)):
            ob["tls"] = {"enabled": True, "server_name": sni or server}
            if insecure:
                ob["tls"]["insecure"] = True
        ws_grpc(ob)
        add_outbound(ob)
    elif t == "vless":
        ob = {"type": "vless", "tag": name, "server": server, "server_port": port,
              "uuid": p.get("uuid", ""), "packet_encoding": "xudp"}
        if p.get("flow"):
            ob["flow"] = p["flow"]
        reality = p.get("reality-opts", {}) or {}
        if reality:
            ob["tls"] = build_tls("reality", sni, p.get("client-fingerprint", ""),
                                  "", reality.get("public-key", ""),
                                  reality.get("short-id", ""), insecure, server)
        elif as_bool(p.get("tls", False)):
            ob["tls"] = build_tls("tls", sni, p.get("client-fingerprint", ""),
                                  "", "", "", insecure, server)
        ws_grpc(ob)
        add_outbound(ob)
    elif t == "trojan":
        ob = {"type": "trojan", "tag": name, "server": server, "server_port": port,
              "password": p.get("password", "")}
        ob["tls"] = {"enabled": True, "server_name": sni or server}
        if insecure:
            ob["tls"]["insecure"] = True
        ws_grpc(ob)
        add_outbound(ob)
    elif t in ("hysteria2", "hy2"):
        ob = {"type": "hysteria2", "tag": name, "server": server,
              "server_port": port, "password": p.get("password", "")}
        ob["tls"] = {"enabled": True, "server_name": sni or server}
        if insecure:
            ob["tls"]["insecure"] = True
        if p.get("obfs"):
            ob["obfs"] = {"type": p["obfs"], "password": p.get("obfs-password", "")}
        add_outbound(ob)
    elif t == "tuic":
        ob = {"type": "tuic", "tag": name, "server": server, "server_port": port,
              "uuid": p.get("uuid", ""), "password": p.get("password", "")}
        if p.get("congestion-controller"):
            ob["congestion_control"] = p["congestion-controller"]
        if p.get("udp-relay-mode"):
            ob["udp_relay_mode"] = p["udp-relay-mode"]
        ob["tls"] = {"enabled": True, "server_name": sni or server}
        if insecure:
            ob["tls"]["insecure"] = True
        add_outbound(ob)
    elif t in ("socks5", "socks"):
        ob = {"type": "socks", "tag": name, "server": server, "server_port": port,
              "version": "5"}
        if p.get("username"):
            ob["username"] = p["username"]
        if p.get("password"):
            ob["password"] = p["password"]
        add_outbound(ob)
    elif t == "http":
        ob = {"type": "http", "tag": name, "server": server, "server_port": port}
        if p.get("username"):
            ob["username"] = p["username"]
        if p.get("password"):
            ob["password"] = p["password"]
        if as_bool(p.get("tls", False)):
            ob["tls"] = {"enabled": True, "server_name": sni or server}
        add_outbound(ob)


def update_clash(text):
    nodes = None
    try:
        import yaml  # PyYAML if present -> full fidelity
        data = yaml.safe_load(text)
        if isinstance(data, dict):
            nodes = data.get("proxies")
    except Exception:
        nodes = None
    if nodes is None:
        nodes = _clash_proxies_fallback(text)
    for p in nodes or []:
        try:
            _clash_node_to_singbox(p)
        except Exception:
            pass


def _clash_proxies_fallback(text):
    """Tolerant parser for the `proxies:` list when PyYAML is unavailable.
    Handles inline flow maps `- {a: b}` and block maps with nested mappings
    (e.g. ws-opts / headers / reality-opts) via an indentation stack."""
    lines = text.splitlines()
    out = []
    in_proxies = False
    cur = None            # current proxy dict
    item_indent = None    # indent of the `- ` marker
    stack = []            # list of (indent, container_dict)

    def flush():
        if cur is not None:
            out.append(cur)

    for raw in lines:
        if re.match(r"^\s*proxies\s*:", raw):
            in_proxies = True
            continue
        if not in_proxies:
            continue
        if raw.strip() == "" or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        stripped = raw.strip()

        # End of the proxies block: a new top-level section.
        if indent == 0 and not stripped.startswith("-") and stripped.endswith(":"):
            break

        if stripped.startswith("- "):
            flush()
            item = stripped[2:].strip()
            if item.startswith("{"):
                out.append(_parse_flow_map(item))
                cur = None
                stack = []
                item_indent = None
                continue
            cur = {}
            item_indent = indent
            stack = [(indent + 2, cur)]
            k, sep, v = item.partition(":")
            if sep:
                _assign(stack, indent + 2, k.strip(), v.strip())
            continue

        if cur is None:
            continue
        # Pop deeper scopes that we have dedented out of.
        while len(stack) > 1 and indent < stack[-1][0]:
            stack.pop()
        k, sep, v = stripped.partition(":")
        if sep:
            _assign(stack, indent, k.strip(), v.strip())
    flush()
    return out


def _assign(stack, indent, key, value):
    # Find the container whose child-indent matches this line's indent.
    container = stack[-1][1]
    for ind, cont in stack:
        if indent >= ind:
            container = cont
    if value == "":
        # Opens a nested mapping.
        child = {}
        container[key] = child
        stack.append((indent + 2, child))
    else:
        container[key] = _yaml_scalar(value)


def _yaml_scalar(v):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        if not inner:
            return []
        return [_yaml_scalar(x) for x in _split_top_commas(inner)]
    if v.lower() in ("true", "false"):
        return v.lower() == "true"
    if re.fullmatch(r"-?\d+", v):
        try:
            return int(v)
        except Exception:
            return v
    if (v.startswith('"') and v.endswith('"')) or \
       (v.startswith("'") and v.endswith("'")):
        return v[1:-1]
    return v


def _parse_flow_map(s):
    s = s.strip()
    if s.startswith("{"):
        s = s[1:]
    if s.endswith("}"):
        s = s[:-1]
    d = {}
    for part in _split_top_commas(s):
        k, _, v = part.partition(":")
        if _:
            d[k.strip()] = _yaml_scalar(v.strip())
    return d


def _split_top_commas(s):
    parts, depth, buf = [], 0, ""
    for ch in s:
        if ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(buf)
            buf = ""
        else:
            buf += ch
    if buf.strip():
        parts.append(buf)
    return parts


# ---------------------------------------------------------------------------
# WireGuard plain-file ([Interface]/[Peer]) -> endpoint
# ---------------------------------------------------------------------------
def parse_wg_file(text):
    section = None
    iface, peer = {}, {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.lower().startswith("[interface]"):
            section = "i"
            continue
        if line.lower().startswith("[peer]"):
            section = "p"
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip().lower()
        v = v.strip()
        (iface if section == "i" else peer)[k] = v
    if not iface.get("privatekey") or not peer.get("publickey"):
        return
    addr = [a for a in re.split(r"[,\s]+", iface.get("address", "")) if a] or ["172.16.0.2/32"]
    endpoint = peer.get("endpoint", "")
    host, _, p = endpoint.partition(":")
    pr = {
        "address": host or endpoint, "port": int(p or 51820),
        "public_key": peer.get("publickey", ""),
        "allowed_ips": [a for a in re.split(r"[,\s]+", peer.get("allowedips", "0.0.0.0/0,::/0")) if a],
    }
    if peer.get("presharedkey"):
        pr["pre_shared_key"] = peer["presharedkey"]
    ep = {
        "type": "wireguard", "tag": host or "wireguard",
        "address": addr, "private_key": iface["privatekey"], "peers": [pr],
    }
    if iface.get("mtu"):
        try:
            ep["mtu"] = int(iface["mtu"])
        except Exception:
            pass
    add_endpoint(ep)


# ---------------------------------------------------------------------------
# Throne RawUpdater::update dispatch (recursive)
# ---------------------------------------------------------------------------
def json_end_idx(s, begin):
    counter, n, i = 1, len(s), begin + 1
    while i < n:
        c = s[i]
        if c == "{":
            counter += 1
        elif c == "}":
            counter -= 1
            if counter == 0:
                return i
        i += 1
    return -1


def disect(s):
    res, idx, n = [], 0, len(s)
    while idx < n:
        c = s[idx]
        if c == "\n":
            idx += 1
            continue
        if c == "{":
            end = json_end_idx(s, idx)
            if end == -1:
                return res
            res.append(s[idx:end + 1])
            idx = end + 1
            continue
        nl = s.find("\n", idx)
        if nl == -1:
            nl = n
        res.append(s[idx:nl])
        idx = nl + 1
    return res


def update(text, need_parse=True):
    if text is None:
        return
    text = text.replace("\r\n", "\n").replace("\r", "\n")

    # 1) whole-content base64
    dec = try_b64_text(text)
    if dec is not None:
        update(dec)
        return

    stripped = text.strip()

    # 2) JSON (sing-box / SIP008 / single object)
    try:
        j = json.loads(stripped)
    except Exception:
        j = None
    if isinstance(j, dict):
        if "outbounds" in j or "endpoints" in j:
            update_singbox(j)
            return
        if "version" in j and "servers" in j:
            update_sip008(j)
            return
        if "server" in j and "type" in j:
            parse_singbox_node(j)
            return
        return

    # 3) Clash
    if re.search(r"(^|\n)\s*proxies\s*:", text):
        update_clash(text)
        return

    # 4) WireGuard file
    if "[Interface]" in text and "[Peer]" in text:
        parse_wg_file(text)
        return

    # 5) multi-line -> Disect, recurse
    if need_parse and "\n" in text:
        for part in disect(text):
            update(part.strip(), False)
        return

    # 6) comments / too short
    if stripped.startswith("//") or stripped.startswith("#") or len(stripped) < 2:
        return

    # 7) json:// link
    if stripped.startswith("json://"):
        parse_json_link(stripped)
        return

    # 8) bare JSON object
    if stripped.startswith("{"):
        try:
            obj = json.loads(stripped)
        except Exception:
            return
        if isinstance(obj, dict):
            if "outbounds" in obj or "endpoints" in obj:
                update_singbox(obj)
            elif "server" in obj:
                parse_singbox_node(obj)
        return

    # 9) share link
    parse_share_link(stripped)


# ---------------------------------------------------------------------------
# Config builder (sing-box 1.13.x schema)
# ---------------------------------------------------------------------------
def build_config():
    # Селектор со всеми спаршенными узлами
    selector = {
        "type": "selector",
        "tag": "proxy",
        "outbounds": list(ORDER_TAGS),
        "default": ORDER_TAGS[0] if ORDER_TAGS else ""
    }

    # Собираем домены всех прокси-узлов, чтобы пустить их DNS-запросы напрямую
    server_domains = []
    for ob in OUTBOUNDS:
        srv = ob.get("server", "")
        # Проверяем, что это строка и она не является чистым IP-адресом
        if srv and isinstance(srv, str) and not re.match(r'^[\d\.:]+$', srv):
            if srv not in server_domains:
                server_domains.append(srv)

    for ep in ENDPOINTS:
        for peer in ep.get("peers", []):
            addr = peer.get("address", "")
            if addr and isinstance(addr, str) and not re.match(r'^[\d\.:]+$', addr):
                if addr not in server_domains:
                    server_domains.append(addr)

    dns_rules = [
        {
            "action": "predefined",
            "answer": "localhost. IN A 127.0.0.1",
            "domain": "localhost",
            "query_type": "A",
            "rcode": "NOERROR"
        },
        {
            "action": "predefined",
            "answer": "localhost. IN AAAA ::1",
            "domain": "localhost",
            "query_type": "AAAA",
            "rcode": "NOERROR"
        }
    ]

    # Маршрутизируем домены прокси-серверов напрямую (как в Throne)
    if server_domains:
        dns_rules.append({
            "action": "route",
            "domain": server_domains,
            "domain_keyword": [],
            "domain_regex": [],
            "domain_suffix": [],
            "rule_set": [],
            "server": "dns-direct",
            "strategy": ""
        })

    # Catch-all правило для dns-direct
    dns_rules.append({
        "action": "route",
        "server": "dns-direct",
        "strategy": ""
    })

    cfg = {
        "certificate": {
            "store": "system"
        },
        "dns": {
            "rules": dns_rules,
            "servers": [
                {
                    "detour": "proxy",
                    "domain_resolver": "dns-local",
                    "server": "8.8.8.8",
                    "tag": "dns-remote",
                    "type": "tls"
                },
                {
                    "domain_resolver": "dns-local",
                    "tag": "dns-direct",
                    "type": "local"
                },
                {
                    "tag": "dns-local",
                    "type": "local"
                }
            ]
        },
        "endpoints": ENDPOINTS,
        "experimental": {
            "cache_file": {
                "enabled": True,
                "store_fakeip": True,
                "store_rdrc": True
            },
            "clash_api": {
                "default_mode": ""
            }
        },
        "inbounds": [
            {
                "listen": "127.0.0.1",
                "listen_port": 5533,
                "tag": "dns-in",
                "type": "direct"
            },
            {
                "listen": "127.0.0.1",
                "listen_port": 2080,
                "tag": "mixed-in",
                "type": "mixed"
            },
            {
                "address": ["172.19.0.1/24"],
                "auto_redirect": True,
                "auto_route": True,
                "mtu": 1500,
                "route_exclude_address": ["127.0.0.0/8"],
                "stack": "system",
                "strict_route": True,
                "tag": "tun-in",
                "type": "tun"
            }
        ],
        "log": {
            "level": "warn"
        },
        "outbounds": [selector] + OUTBOUNDS + [{"tag": "direct", "type": "direct"}],
        "route": {
            "auto_detect_interface": True,
            "default_domain_resolver": {
                "server": "dns-direct",
                "strategy": ""
            },
            "final": "proxy",
            "find_process": True,
            "rule_set": [],
            "rules": [
                {
                    "action": "sniff",
                    "inbound": "dns-in"
                },
                {
                    "action": "hijack-dns",
                    "inbound": "dns-in",
                    "protocol": "dns"
                },
                {
                    "action": "reject",
                    "inbound": "dns-in"
                },
                {
                    "action": "sniff",
                    "inbound": ["mixed-in", "tun-in"]
                },
                {
                    "action": "hijack-dns",
                    "protocol": "dns"
                }
            ]
        }
    }

    return cfg


def main():
    if len(sys.argv) < 3:
        sys.exit(1)
    config_path, raw_file = sys.argv[1], sys.argv[2]
    try:
        with open(raw_file, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read().strip()
    except Exception:
        sys.exit(1)
    if not raw:
        sys.exit(1)

    update(raw)

    if not ORDER_TAGS:
        sys.exit(1)

    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(build_config(), f, indent=2, ensure_ascii=False)
    sys.stderr.write("parsed %d node(s)\n" % len(ORDER_TAGS))


if __name__ == "__main__":
    main()
