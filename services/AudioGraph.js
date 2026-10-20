.pragma library

// Pure audio graph logic (services/AudioDevices feeds it plain snapshots).
// One row per PHYSICAL device: a filter (DSP filter-chain, EQ, the shell's
// own voice processing) over a device and the raw device are the same
// "Speakers" to the user. A node's endpoint = follow filter link groups
// (node.link-group "filter-chain-*" / "echo-cancel-*": the group's
// Audio/Sink feeds its own Stream/Output, linked on to the next node; a
// source is fed by its group's capture stream) down to the first
// non-filter node. Rows are keyed by the endpoint's STABLE identity (card
// name + ALSA pcm name, Bluetooth address, else the node name) — the T2
// DSP speakers end in the internal hw_Audio_0 and the raw HiFi Speaker
// sink (a UCM split loopback) is pcm "Speaker" of the same card too. The
// row's node = the default one if it is in the group, else the shallowest
// filter, else the raw node.
//
// node:  { id, name, desc, nick, cls, lg, devId, api, bus, icon, form,
//          address, props }
// group: { src, dst } (PwLinkGroup node ids)
// pulse: { sinks, sources, cards } = pactl -f json lists ([] when unknown)
// cfg:   Config audio (hideDevices, deviceNames)

function isFilter(n) {
    return /^(filter-chain|echo-cancel)/.test(n.lg ?? "") || /^effect_(input|output)\./.test(n.name ?? "")
        || (n.name ?? "").startsWith("flicker_voice");
}

function isBt(n) {
    return n.api === "bluez5" || (n.name ?? "").startsWith("bluez_");
}

function isHdmi(n) {
    return /hdmi|displayport/i.test(`${n.name ?? ""} ${n.desc ?? ""}`);
}

function endpoint(n, nodes, byId, groups, sink, depth) {
    if (depth > 6 || !isFilter(n))
        return { node: n, depth: depth };
    // The group's own stream on the device side (never the echo
    // canceller's sink-monitor reference stream).
    const streamCls = sink ? "Stream/Output" : "Stream/Input";
    const mate = nodes.find(m => m.id !== n.id && m.lg === n.lg && (m.cls ?? "").startsWith(streamCls)
        && `${m.props?.["stream.monitor"] ?? ""}` !== "true");
    if (!mate)
        return { node: n, depth: depth };
    const g = groups.find(l => sink ? l.src === mate.id : l.dst === mate.id);
    const next = g ? byId[sink ? g.dst : g.src] : null;
    return next ? endpoint(next, nodes, byId, groups, sink, depth + 1) : { node: n, depth: depth };
}

// Survives reboots / PipeWire restarts (device.id does not).
function stableKey(e) {
    const p = e.props ?? {};
    if (isBt(e) && e.address)
        return `bt/${`${e.address}`.toUpperCase()}`;
    const card = p["api.alsa.card.name"] ?? p["alsa.card_name"];
    if (card !== undefined)
        return `${card}/${p["alsa.name"] ?? e.nick ?? e.name}`;
    return e.name;
}

function matches(n, patterns) {
    const hay = `${n.name ?? ""}\n${n.desc ?? ""}`.toLowerCase();
    return (patterns ?? []).some(p => p && hay.indexOf(`${p}`.toLowerCase()) !== -1);
}

// pactl card of a node (card properties carry the device object id).
function cardOf(n, cards) {
    if (n.devId === undefined || n.devId === null)
        return null;
    return (cards ?? []).find(c => `${c.properties?.["object.id"] ?? c.index}` === `${n.devId}`) ?? null;
}

function portType(port, card) {
    const t = card?.ports?.[port]?.type ?? "";
    if (t)
        return t;
    const m = /\]\s*(\w+)/.exec(port ?? "");
    return m ? m[1] : "";
}

// Generic names for built-in ports (I18n keys; the UI translates them).
const PORT_LABELS = {
    Speaker: "Built-in Speakers",
    Headphones: "Headphones",
    Headset: "Headset Microphone",
    Mic: "Built-in Microphone",
    Line: "Line"
};

function kindOf(n, type, sink) {
    if (isBt(n))
        return /headset/.test(n.icon ?? "") || n.form === "headset" ? "btHeadset" : /speaker/.test(n.icon ?? "") || n.form === "speaker" ? "btSpeaker" : "btHeadphones";
    if (isHdmi(n))
        return "hdmi";
    if (n.bus === "usb")
        return n.form === "headset" || /headset/.test(n.icon ?? "") ? "usbHeadset" : "usb";
    if (type === "Headphones")
        return "headphones";
    if (type === "Headset")
        return "headset";
    return sink ? "speaker" : "mic";
}

// Built-in first, then wired, USB, Bluetooth, displays.
const KIND_RANK = { speaker: 0, mic: 0, headphones: 1, headset: 1, usb: 2, usbHeadset: 2, btHeadphones: 3, btHeadset: 3, btSpeaker: 3, hdmi: 4 };

// Headphone-like outputs (their own volume cap, "listen to yourself").
function isPersonal(kind) {
    return /^(headphones|headset|usbHeadset|btHeadphones|btHeadset)$/.test(kind ?? "");
}

function pulseOf(n, list) {
    return (list ?? []).find(s => s.name === n.name) ?? null;
}

// Output (sink = true) or input rows:
//   { key, nodeId, name, label, translate, kind, isDefault, available,
//     hidden, action: { type: "node" | "port" | "profile" | "none", ... },
//     bt: { card, address } | null, card, port, members: [{ id, name,
//     desc, depth }], sub }
// `order` = known keys in the user's priority order (AudioDevices):
// present rows sort by it, unknown ones after by kind and name.
// Hidden devices (cfg.hideDevices = row keys or name patterns) are left
// out unless `showHidden`.
function devices(nodes, groups, pulse, defaultId, sink, cfg, order, showHidden) {
    const byId = {};
    for (const n of nodes)
        byId[n.id] = n;
    const cls = sink ? "Audio/Sink" : "Audio/Source";
    const list = sink ? pulse.sinks : pulse.sources;
    const names = cfg?.deviceNames ?? {};
    const hide = cfg?.hideDevices ?? [];
    const groupsByKey = {};
    for (const n of nodes) {
        if (n.cls !== cls)
            continue;
        const e = endpoint(n, nodes, byId, groups, sink, 0);
        const key = stableKey(e.node);
        (groupsByKey[key] = groupsByKey[key] ?? []).push({ node: n, depth: e.depth, end: e.node });
    }
    const covered = {};
    const rows = [];
    for (const key in groupsByKey) {
        const members = groupsByKey[key];
        const pick = members.find(m => m.node.id === defaultId)
            ?? members.slice().sort((a, b) => (a.depth || 99) - (b.depth || 99))[0];
        const n = pick.node;
        // Active port: of any member pactl knows (filter nodes have none).
        let port = "", card = null;
        for (const m of members) {
            const p = pulseOf(m.node, list);
            for (const pp of p?.ports ?? [])
                covered[`${m.node.devId}|${pp.name}`] = true;
            if (!port && p?.active_port) {
                port = p.active_port;
                card = cardOf(m.node, pulse.cards);
            }
        }
        card = card ?? cardOf(pick.end, pulse.cards);
        const type = port ? portType(port, card) : (/head/i.test(pick.end.nick ?? "") ? "Headphones" : "");
        const kind = kindOf(pick.end, type, sink);
        let label = names[key] ?? "", translate = false;
        if (!label)
            for (const pat in names)
                if (pat.indexOf("/") === -1 && members.some(m => matches(m.node, [pat])))
                    label = names[pat];
        if (!label && isBt(pick.end))
            label = pick.end.desc || n.desc;
        else if (!label && pick.end.bus === "pci" && !isHdmi(pick.end) && PORT_LABELS[type || (sink ? "Speaker" : "Mic")]) {
            label = PORT_LABELS[type || (sink ? "Speaker" : "Mic")];
            translate = true;
        }
        if (!label)
            label = pick.end.desc || n.desc || n.nick || n.name;
        const hidden = hide.includes(key) || members.some(m => matches(m.node, hide.filter(h => h.indexOf("/") === -1)));
        if (hidden && !showHidden)
            continue;
        rows.push({
            key: key,
            nodeId: n.id,
            name: n.name,
            label: label,
            translate: translate,
            kind: kind,
            isDefault: members.some(m => m.node.id === defaultId),
            available: true,
            hidden: hidden,
            action: { type: "node", nodeId: n.id },
            bt: isBt(pick.end) ? { card: card?.name ?? "", address: pick.end.address ?? "" } : null,
            card: card?.name ?? "",
            port: port,
            members: members.map(m => ({ id: m.node.id, name: m.node.name, desc: m.node.desc, depth: m.depth }))
                .sort((a, b) => a.depth - b.depth),
            // Endpoint not found (links not read yet, start-up): the key is
            // a filter node's own name — not one to remember.
            resolved: !isFilter(pick.end),
            sub: ""
        });
    }
    // Card ports no node plays through now (other profile / port), ALSA
    // only: plugged = a row that switches to it, unplugged headphones /
    // headset mic = a dimmed "Not plugged in" row.
    for (const c of pulse.cards ?? []) {
        if ((c.name ?? "").startsWith("bluez_"))
            continue;
        const devId = c.properties?.["object.id"] ?? c.index;
        for (const pname in c.ports ?? {}) {
            const p = c.ports[pname];
            if (sink !== pname.startsWith("[Out]") || covered[`${devId}|${pname}`])
                continue;
            const type = p.type ?? portType(pname, c);
            const unplugged = p.availability === "not available";
            if (unplugged && type !== "Headphones" && type !== "Headset")
                continue;
            // A sink of this card that can switch ports: set-sink-port.
            const owner = (list ?? []).find(s => (s.ports ?? []).some(pp => pp.name === pname));
            let action = null;
            if (owner)
                action = { type: "port", target: owner.name, port: pname };
            else {
                const prof = (p.profiles ?? []).map(name => ({ name: name, info: c.profiles?.[name] }))
                    .filter(x => x.info && x.info.available !== false)
                    .sort((a, b) => (b.info.priority ?? 0) - (a.info.priority ?? 0))[0];
                if (prof)
                    action = { type: "profile", card: c.name, profile: prof.name };
            }
            if (!unplugged && !action)
                continue;
            const key = `port:${c.name}/${pname}`;
            if (hide.includes(key) && !showHidden)
                continue;
            rows.push({
                key: key,
                nodeId: -1,
                name: "",
                label: names[key] ?? PORT_LABELS[type] ?? p.description ?? pname,
                translate: !names[key] && !!PORT_LABELS[type],
                kind: kindOf({}, type, sink),
                isDefault: false,
                available: !unplugged,
                hidden: hide.includes(key),
                action: action ?? { type: "none" },
                bt: null,
                card: c.name,
                port: pname,
                members: [],
                sub: unplugged ? "unplugged" : ""
            });
        }
    }
    // A Bluetooth headset in music mode has no microphone node: offer it
    // (the tap switches the card to its call profile).
    if (!sink) {
        for (const c of pulse.cards ?? []) {
            if (!(c.name ?? "").startsWith("bluez_") || !isA2dp(c.active_profile))
                continue;
            const call = bestProfile(c, isCall);
            if (!call)
                continue;
            const address = `${c.properties?.["api.bluez5.address"] ?? ""}`.toUpperCase();
            rows.push({
                key: `bt/${address}`,
                nodeId: -1,
                name: "",
                label: names[`bt/${address}`] ?? c.properties?.["device.description"] ?? c.name,
                translate: false,
                kind: "btHeadset",
                isDefault: false,
                available: true,
                hidden: false,
                action: { type: "profile", card: c.name, profile: call },
                bt: { card: c.name, address: address },
                card: c.name,
                port: "",
                members: [],
                sub: "callMode"
            });
        }
    }
    const rank = k => {
        const i = (order ?? []).indexOf(k);
        return i < 0 ? 1e6 : i;
    };
    return rows.sort((a, b) => (rank(a.key) - rank(b.key))
        || ((KIND_RANK[a.kind] ?? 5) - (KIND_RANK[b.kind] ?? 5))
        || (a.available === b.available ? 0 : a.available ? -1 : 1)
        || `${a.label}`.localeCompare(`${b.label}`));
}

function isA2dp(profile) {
    return /^a2dp/.test(profile ?? "");
}
function isCall(profile) {
    return /^(headset-head-unit|handsfree|hfp|hsp)/.test(profile ?? "");
}
// Highest-priority available profile of the card that passes `test`.
function bestProfile(card, test) {
    const all = Object.keys(card?.profiles ?? {}).filter(p => test(p) && card.profiles[p].available !== false);
    all.sort((a, b) => (card.profiles[b].priority ?? 0) - (card.profiles[a].priority ?? 0));
    return all[0] ?? "";
}
// { music, calls, active: "music" | "calls" | "" } of a Bluetooth card;
// null when it cannot do both.
function btModes(cards, cardName) {
    const c = (cards ?? []).find(x => x.name === cardName);
    if (!c)
        return null;
    const music = bestProfile(c, isA2dp), calls = bestProfile(c, isCall);
    if (!music || !calls)
        return null;
    return { music: music, calls: calls, active: isA2dp(c.active_profile) ? "music" : isCall(c.active_profile) ? "calls" : "" };
}

// Profiles of a card for a choice: [{ value, label }] (available ones,
// highest priority first) and the active one.
function profiles(cards, cardName) {
    const c = (cards ?? []).find(x => x.name === cardName);
    if (!c)
        return { options: [], active: "" };
    const names = Object.keys(c.profiles ?? {}).filter(p => p === c.active_profile || c.profiles[p].available !== false);
    names.sort((a, b) => (c.profiles[b].priority ?? 0) - (c.profiles[a].priority ?? 0));
    return { options: names.map(p => ({ value: p, label: c.profiles[p].description || p })), active: c.active_profile ?? "" };
}

// Latency offset of a card port in ms ("12000 usec" in pactl JSON).
function latencyMs(cards, cardName, port) {
    const c = (cards ?? []).find(x => x.name === cardName);
    const v = `${c?.ports?.[port]?.latency_offset ?? "0"}`;
    return Math.round((parseInt(v) || 0) / 1000);
}

// Playback streams of apps (filter / loopback members are infrastructure):
//   { id, serial, app, media, icon, target } — target = node id it plays to.
function streams(nodes, groups) {
    return nodes.filter(n => n.cls === "Stream/Output/Audio" && !n.lg && !(n.name ?? "").startsWith("flicker_"))
        .map(n => {
            const p = n.props ?? {};
            const g = groups.find(l => l.src === n.id);
            return {
                id: n.id,
                serial: `${p["object.serial"] ?? ""}`,
                app: p["application.name"] || p["application.process.binary"] || n.desc || n.name,
                media: p["media.name"] ?? "",
                icon: p["application.icon-name"] || p["application.process.binary"] || "",
                target: g ? g.dst : -1
            };
        });
}

// Row key of the device a node belongs to (stream target → output row).
function rowOfNode(rows, nodes, groups, nodeId, sink) {
    const byId = {};
    for (const n of nodes)
        byId[n.id] = n;
    const n = byId[nodeId];
    if (!n)
        return "";
    const key = stableKey(endpoint(n, nodes, byId, groups, sink, 0).node);
    return rows.some(r => r.key === key) ? key : "";
}
