.pragma library

// Sound section helpers: the device lists (services/AudioDevices: present
// devices + the known ones that are away, in the user's priority order),
// the drill-down page of one device, the app outputs WirePlumber
// remembers (services/AudioPolicy.routes). Rows of a device carry a `ref`
// { key, sink }; their store is "audioDev" (SettingsWindow.valueOf /
// setValue look the live device up by key). A page's groups are generated
// (`generate: "audioDevice"`) so they follow the device as it comes and
// goes.

// Present rows first in their (priority) order, then the known ones that
// are away. { key, label, translate, kind, row | null }
function entries(devices, sink) {
    const rows = sink ? devices.allOutputs : devices.allInputs;
    const known = sink ? devices.known.outputs : devices.known.inputs;
    const order = known.map(k => k.key);
    const out = rows.filter(r => r.nodeId >= 0 || r.sub === "unplugged" || r.action?.type === "profile" || r.action?.type === "port")
        .map(r => ({ key: r.key, label: r.label, translate: r.translate, kind: r.kind, row: r }));
    for (const k of known)
        if (!out.some(e => e.key === k.key))
            out.push({ key: k.key, label: k.label, translate: !!k.translate, kind: k.kind, row: null });
    const rank = k => {
        const i = order.indexOf(k);
        return i < 0 ? 1e6 : i;
    };
    return out.sort((a, b) => rank(a.key) - rank(b.key));
}

// "current" | "connected" | "unplugged" | "away"
function status(entry) {
    const r = entry?.row;
    if (!r)
        return "away";
    if (r.isDefault)
        return "current";
    return r.available ? "connected" : "unplugged";
}

const STATUS = [
    { value: "current", label: "In use" },
    { value: "connected", label: "Connected" },
    { value: "unplugged", label: "Not plugged in" },
    { value: "away", label: "Not connected" }
];

function label(entry, tr) {
    return entry.translate ? tr(entry.label) : entry.label;
}

// The generated device list group.
function listGroup(group, devices, sink, hidden, tr) {
    const rows = entries(devices, sink).map(e => {
        const st = status(e);
        const isHidden = hidden.includes(e.key);
        return {
            kind: "page",
            label: label(e, tr),
            detail: isHidden ? "Hidden" : (STATUS.find(s => s.value === st)?.label ?? ""),
            muted: st === "away" || st === "unplugged",
            page: { title: label(e, tr), groups: [{ generate: "audioDevice", ref: { key: e.key, sink: sink }, rows: [] }] }
        };
    });
    if (rows.length === 0)
        rows.push({ kind: "action", label: sink ? "No outputs" : "No microphones", action: "audioNone" });
    return Object.assign({}, group, { rows: rows });
}

// The device page: groups depend on what the device has (a card with
// profiles, a port with a latency offset, left / right channels…).
function deviceGroups(ref, devices, policy, tr) {
    const e = entries(devices, ref.sink).find(x => x.key === ref.key) ?? { key: ref.key, label: ref.key, row: null };
    const r = e.row;
    const dev = (key, extra) => Object.assign({ store: "audioDev", ref: ref, key: key }, extra);
    const act = (action, extra) => Object.assign({ kind: "action", action: action, ref: ref }, extra);
    const groups = [];
    groups.push({ rows: [
        dev("status", { label: "Status", kind: "info", options: STATUS }),
        act("audioUse", { label: ref.sink ? "Use for output" : "Use for input" })
    ] });
    groups.push({ footer: "The name shows in Quick Settings. Hidden devices stay usable from here.", rows: [
        dev("name", { label: "Name", kind: "text", allowEmpty: true, placeholder: label(e, tr) }),
        dev("hidden", { label: "Hide in Quick Settings", kind: "bool" })
    ] });
    if (r && r.members.length > 1)
        groups.push({ footer: "The same device with or without the signal processing (DSP, equalizer, noise suppression) in front of it.", rows: [
            dev("variant", { label: "Processing", kind: "choice", optionsFrom: "audioVariants" })
        ] });
    const profileRows = [];
    if (r && r.card)
        profileRows.push(dev("profile", { label: r.bt ? "Profile and codec" : "Profile", kind: "choice", optionsFrom: "audioProfiles" }));
    if (r && r.card && r.port)
        profileRows.push(dev("latency", { label: "Latency offset", kind: "number", min: -500, max: 500, step: 10, suffix: " ms" }));
    if (profileRows.length > 0)
        groups.push({ footer: r?.bt ? "Music profiles differ by codec; call profiles carry the microphone. A latency offset lines the sound up with video." : "A latency offset lines the sound up with video.", rows: profileRows });
    if (ref.sink && r && r.nodeId >= 0) {
        groups.push({ footer: "Kept for this device while it is in use. Negative = left.", rows: [
            dev("balance", { label: "Balance", kind: "number", slider: true, min: -1, max: 1, step: 0.05, scale: 0.01, suffix: " %" }),
            act("audioCenter", { label: "Center" })
        ] });
        groups.push({ rows: [
            act("audioTestLeft", { label: "Test left channel" }),
            act("audioTestRight", { label: "Test right channel" })
        ] });
    }
    groups.push({ title: "Priority", footer: "When the device in use goes away, the first available one in the list takes over.", rows: [
        act("audioUp", { label: "Move up" }),
        act("audioDown", { label: "Move down" }),
        act("audioForget", { label: "Forget device", destructive: true, confirm: "Tap again to forget" })
    ] });
    return groups;
}

// App outputs WirePlumber remembers: tap = forget (the app follows the
// current output again).
function routesGroup(group, policy, devices, tr) {
    const rows = (policy?.routes ?? []).map(rt => {
        const row = devices.allOutputs.find(r => r.members.some(m => m.name === rt.target));
        const target = row ? (row.translate ? tr(row.label) : row.label) : rt.target;
        return {
            kind: "action",
            label: rt.kind === "media.role" ? tr("%1 (role)").arg(rt.app) : rt.app,
            detail: target,
            action: "audioForgetRoute",
            route: rt.key,
            confirm: "Tap again to forget"
        };
    });
    if (rows.length > 0)
        rows.push({ kind: "action", label: "Forget all", action: "audioForgetRoutes", destructive: true, confirm: "Tap again to forget all" });
    else
        rows.push({ kind: "action", label: "None remembered", action: "audioNone" });
    return Object.assign({}, group, { rows: rows });
}
