.pragma library

// VPN section helpers: the split-routing rule list (Config `vpn.routing`,
// syntax in scripts/vpn/routing.py) as generated rows, the drill-down page
// of one rule, rule templates, and a client-side copy of routing.py's
// matcher check (errors show while editing, not only on Apply). A rule
// page holds a `ref` ({ index }) instead of a fixed index: moving the rule
// moves the ref with it; a deleted rule's ref keeps a copy (`gone`,
// index -1) for the page sliding away.

const ACTIONS = [
    { value: "proxy", label: "Proxy" },
    { value: "direct", label: "Direct" },
    { value: "block", label: "Block" }
];

// routing.py: FIELDS + the list / protocol kinds, SOURCES, NAME_RE.
const KINDS = ["domain", "full", "keyword", "regexp", "ip", "process", "path", "geosite", "geoip", "protocol"];
const SOURCES = ["runetfreedom", "metacubex", "sagernet"];
const NAME_RE = /^[a-z0-9][a-z0-9._!-]*$/;

// Added to the end of the list (Add from template).
const TEMPLATES = [
    { label: "Russian sites direct", rule: { action: "direct", match: ["geoip:ru", "geosite:category-ru", "domain:ru", "domain:su", "domain:xn--p1ai"] } },
    { label: "Blocked in Russia through VPN", rule: { action: "proxy", match: ["geosite:ru-blocked", "geoip:ru-blocked"] } },
    { label: "Block ads", rule: { action: "block", match: ["geosite:category-ads-all"] } },
    { label: "Torrents direct", rule: { action: "direct", match: ["protocol:bittorrent"] } }
];

// Python's ipaddress.ip_network(v, strict=False), near enough: IPv4 with
// an optional /len or /netmask, IPv6 with an optional /len.
function isIp(v) {
    const [addr, len, extra] = v.split("/");
    if (extra !== undefined)
        return false;
    const v4 = a => /^\d{1,3}(\.\d{1,3}){3}$/.test(a) && a.split(".").every(o => +o <= 255);
    if (v4(addr))
        return len === undefined || /^\d{1,2}$/.test(len) && +len <= 32 || v4(len);
    if (!addr.includes(":") || !/^[0-9a-fA-F:.]+$/.test(addr) || addr.split("::").length > 2)
        return false;
    if (addr.split(":").length > 8 + (addr.includes("::") ? 1 : 0))
        return false;
    return len === undefined || /^\d{1,3}$/.test(len) && +len <= 128;
}

// One matcher (routing.py parse()): "" or the translated error.
function matcherError(m, tr) {
    const i = m.indexOf(":");
    let kind = i < 0 ? "" : m.slice(0, i);
    let value = i < 0 ? "" : m.slice(i + 1);
    if (!KINDS.includes(kind)) {
        kind = isIp(m) ? "ip" : "domain";
        value = m;
    }
    value = value.trim();
    if (value === "")
        return tr("%1: empty value").arg(m);
    if (kind === "geosite" || kind === "geoip") {
        const [name, source] = value.toLowerCase().split("@");
        if (!NAME_RE.test(name))
            return tr("%1: bad list name").arg(m);
        if (source !== undefined && !SOURCES.includes(source))
            return tr("%1: unknown source (%2)").arg(m).arg(SOURCES.join(", "));
    } else if (kind === "ip" && !isIp(value)) {
        return tr("%1: not an address / CIDR").arg(m);
    } else if (kind === "regexp") {
        try {
            new RegExp(value);
        } catch (e) {
            return tr("%1: bad regular expression").arg(m);
        }
    }
    return "";
}

function ruleError(rule, tr) {
    for (const m of [].concat(rule?.match ?? [])) {
        const e = matcherError(String(m).trim(), tr);
        if (e)
            return e;
    }
    return "";
}

// The first enabled rule that routing.py would reject (disabled ones it
// skips unparsed).
function routingError(rules, tr) {
    for (let i = 0; i < rules.length; i++) {
        if (rules[i]?.enabled === false)
            continue;
        const e = ruleError(rules[i], tr);
        if (e)
            return tr("Rule %1: %2").arg(i + 1).arg(e);
    }
    return "";
}

function isEmpty(rule) {
    return [].concat(rule?.match ?? []).filter(m => String(m).trim() !== "").length === 0;
}

// The list row label: the rule's name, else "geoip:ru, geosite:youtube +3".
function summary(rule, tr) {
    if ((rule.name ?? "").trim() !== "")
        return rule.name.trim();
    const m = rule.match ?? [];
    if (m.length === 0)
        return tr("No matches");
    const shown = m.slice(0, 2).join(", ");
    return m.length > 2 ? `${shown} +${m.length - 2}` : shown;
}

function actionLabel(a) {
    return (ACTIONS.find(o => o.value === a) ?? ACTIONS[0]).label;
}

function rulePage(ref) {
    const row = (key, extra) => Object.assign({ store: "vpnRule", ref: ref, key: key }, extra);
    return {
        title: "Rule",
        ruleRef: ref,
        groups: [
            { footer: "Rules are tried top to bottom; the first one that matches decides.", rows: [
                row("name", { label: "Name", kind: "text", allowEmpty: true, placeholder: "Optional" }),
                row("enabled", { label: "Enabled", kind: "bool" }),
                row("action", { label: "Traffic", kind: "choice", segments: true, options: ACTIONS })
            ] },
            { title: "Matches", footerFrom: "vpnRule", ref: ref, footer: "Space-separated. domain: (with subdomains), full:, keyword:, regexp:, ip: (address or CIDR), process:, path:, protocol: (bittorrent, quic…), geosite:name, geoip:name; @source pins a list (runetfreedom, metacubex, sagernet). A bare value is an address or a domain. A rule left without matches is removed.", rows: [
                row("match", { label: "Match", kind: "text", array: true, wide: true, allowEmpty: true, placeholder: "geosite:youtube domain:example.com" })
            ] },
            { rows: [
                { kind: "action", label: "Move up", action: "ruleUp", ref: ref },
                { kind: "action", label: "Move down", action: "ruleDown", ref: ref },
                { kind: "action", label: "Delete rule", action: "ruleDelete", ref: ref, destructive: true, confirm: "Tap again to delete" }
            ] }
        ]
    };
}

const TEMPLATES_PAGE = {
    title: "Templates",
    groups: [
        { footer: "Added to the end of the list: move it up if an earlier rule catches the same traffic. “Blocked in Russia through VPN” is for Everything else = Direct.", rows: TEMPLATES.map(t => ({
                kind: "action", label: t.label, detail: actionLabel(t.rule.action), action: "ruleAddTemplate", rule: t.rule
            })) }
    ]
};

// The generated group: one row per rule (opens its page), then "Add rule"
// and the templates.
function rulesGroup(group, rules, tr) {
    const rows = rules.map(r => r ?? {}).map((r, i) => ({
        kind: "page",
        label: summary(r, tr),
        detail: r.enabled !== false && ruleError(r, tr) ? "Invalid" : actionLabel(r.action),
        muted: r.enabled === false,
        page: rulePage({ index: i })
    }));
    rows.push({ kind: "action", label: "Add rule", action: "ruleAdd" });
    rows.push({ kind: "page", label: "Add from template", page: TEMPLATES_PAGE });
    return Object.assign({}, group, { rows: rows });
}
