import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// Display configuration (settings → Displays) over wlr-output-management
// (`wlr-randr`, served by niri and driftwm alike):
//   outputs — the heads (scripts/displays/state.sh), phantom ones without
//     modes left out; `pending` = edits not applied yet ({ name: { enabled,
//     mode, scale, transform, x, y } }, only the keys that differ);
//   apply() — every output in one wlr-randr call, then `confirming`: the
//     change is reverted after Config displays.confirmSec unless keep();
//   kept layouts — Quickshell.statePath("displays.json"), one per SET of
//     connected outputs (make|model|serial), restored when that set shows
//     up (start, hotplug; displays.restore). The compositor's own output
//     config applies first, ours after it.
// Modes: the current mode is never sent again (niri re-picks a custom mode
// sent back through set_mode: the native one wins). A custom mode goes as
// --custom-mode; on driftwm every mode does (it tries an exact EDID match
// first, wlr's mode objects are not trusted there). niri re-derives a custom
// mode's refresh (CVT): 60 → 59.93, 59.93 → 59.84, so a live custom refresh
// near a whole number is sent rounded.
Scope {
    id: root
    required property var compositor

    readonly property var cfg: Config.data.displays ?? {}
    readonly property string backend: root.compositor?.detect?.backendName ?? ""
    readonly property string scripts: Quickshell.shellDir + "/scripts/displays/"

    property bool available: true
    property var outputs: []
    property var niriCustom: ({})
    property var pending: ({})
    readonly property bool hasPending: Object.keys(root.pending).length > 0
    // At least one output stays on.
    readonly property bool canApply: root.hasPending && !root.confirming && !applyProc.running
        && root.outputs.some(o => root.effective(o).enabled)
    property string error: ""

    property bool confirming: false
    property int confirmLeft: 0
    property var previous: []
    property var applied: []

    property var profiles: ({})
    property string restoredKey: ""

    // ---- state ----

    function refresh(): void {
        if (stateProc.running) {
            stateProc.again = true;
            return;
        }
        stateProc.command = [root.scripts + "state.sh"];
        stateProc.running = true;
    }

    Process {
        id: stateProc
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(this.text);
                    const custom = {};
                    // niri: { name: output }.
                    for (const n of Object.values(s.niri ?? {}))
                        custom[n.name] = !!n.is_custom_mode;
                    root.niriCustom = custom;
                    root.outputs = (s.wlr ?? []).filter(o => (o.modes ?? []).length > 0);
                    root.available = true;
                    root.outputsRead();
                } catch (e) {
                    console.warn("[displays] bad state:", e);
                }
            }
        }
        onExited: code => {
            if (code === 127)
                root.available = false;
            if (stateProc.again) {
                stateProc.again = false;
                root.refresh();
            }
        }
    }

    // A new set of outputs drops what was being edited for the old one,
    // then gets its kept layout back.
    function outputsRead(): void {
        const key = root.setKey();
        if (key === root.restoredKey)
            return;
        root.restoredKey = key;
        root.pending = {};
        if (root.confirming) {
            root.confirming = false;
            confirmTimer.stop();
        }
        root.restore();
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            refreshTimer.restart();
        }
    }

    // A mode / scale change from elsewhere (compositor config, niri msg)
    // keeps the screen list: each screen's geometry is watched too.
    Variants {
        model: Quickshell.screens

        QtObject {
            required property var modelData
            readonly property string geometry: `${modelData.width}x${modelData.height}@${modelData.devicePixelRatio}`
            onGeometryChanged: refreshTimer.restart()
        }
    }

    // Lets the compositor's own hotplug handling settle first.
    Timer {
        id: refreshTimer
        interval: root.cfg.refreshDelayMs ?? 800
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    // ---- identity ----

    function idOf(o: var): string {
        return `${o.make ?? ""}|${o.model ?? ""}|${o.serial ?? o.name}`;
    }

    function setKey(): string {
        return root.outputs.map(o => root.idOf(o)).sort().join("+");
    }

    function find(name: string): var {
        return root.outputs.find(o => o.name === name) ?? null;
    }

    // "DELL P2214H", the built-in panel by its connector kind.
    function label(o: var): string {
        if (/^(eDP|LVDS|DSI)/.test(o.name))
            return I18n.tr("Built-in display");
        const m = o.model && o.model !== "Unknown" ? o.model : "";
        return m || o.description || o.name;
    }

    // ---- configs: { name, enabled, mode { width, height, refresh, custom },
    // scale, transform, x, y } ----

    function nearWhole(hz: real): real {
        const r = Math.round(hz);
        return Math.abs(hz - r) < 0.2 ? r : hz;
    }

    function liveCfg(o: var): var {
        const cur = (o.modes ?? []).find(m => m.current) ?? null;
        const custom = !!root.niriCustom[o.name] && !!cur;
        const fallback = (o.modes ?? []).find(m => m.preferred) ?? (o.modes ?? [])[0] ?? null;
        const m = cur ?? fallback;
        return {
            name: o.name,
            enabled: !!o.enabled,
            mode: m ? { width: m.width, height: m.height, refresh: custom ? root.nearWhole(m.refresh) : m.refresh, custom: custom } : null,
            scale: o.scale ?? 1,
            transform: o.transform ?? "normal",
            x: o.position?.x ?? 0,
            y: o.position?.y ?? 0
        };
    }

    function effective(o: var): var {
        return Object.assign(root.liveCfg(o), root.pending[o.name] ?? {});
    }

    function sameMode(a: var, b: var): bool {
        return !!a && !!b && a.width === b.width && a.height === b.height
            && Math.abs(a.refresh - b.refresh) < 0.5 && !!a.custom === !!b.custom;
    }

    function sameCfg(a: var, b: var): bool {
        if (a.enabled !== b.enabled)
            return false;
        if (!a.enabled)
            return true;
        return root.sameMode(a.mode, b.mode) && Math.abs(a.scale - b.scale) < 0.005
            && a.transform === b.transform && a.x === b.x && a.y === b.y;
    }

    // Logical size (what the layout uses).
    function sizeOf(c: var): var {
        const s = Math.max(0.1, c.scale || 1);
        let w = Math.round((c.mode?.width ?? 1920) / s);
        let h = Math.round((c.mode?.height ?? 1080) / s);
        if (/90|270/.test(c.transform ?? ""))
            [w, h] = [h, w];
        return { w: w, h: h };
    }

    // Enabled outputs as logical rects, pending edits included.
    function layout(): var {
        return root.outputs.map(o => {
            const c = root.effective(o);
            const sz = root.sizeOf(c);
            return { name: o.name, label: root.label(o), enabled: c.enabled, x: c.x, y: c.y, w: sz.w, h: sz.h, mode: c.mode };
        }).filter(r => r.enabled);
    }

    // ---- editing ----

    function modeKey(m: var): string {
        return m ? `${m.width}x${m.height}@${Number(m.refresh).toFixed(3)}` : "";
    }

    function hz(r: real): string {
        return String(Number(Number(r).toFixed(2)));
    }

    function modeOptions(name: string): var {
        const o = root.find(name);
        if (!o)
            return [];
        const seen = {};
        const opts = [];
        const cur = root.liveCfg(o);
        for (const m of o.modes) {
            const custom = m.current && cur.mode?.custom;
            const mode = { width: m.width, height: m.height, refresh: custom ? cur.mode.refresh : m.refresh, custom: !!custom };
            const k = root.modeKey(mode);
            if (seen[k])
                continue;
            seen[k] = true;
            let text = I18n.tr("%1 × %2, %3 Hz").arg(m.width).arg(m.height).arg(root.hz(m.refresh));
            if (m.preferred)
                text += " · " + I18n.tr("native");
            else if (custom)
                text += " · " + I18n.tr("custom");
            opts.push({ value: k, label: text, mode: mode });
        }
        const eff = root.effective(o).mode;
        if (eff && !seen[root.modeKey(eff)])
            opts.push({ value: root.modeKey(eff), label: I18n.tr("%1 × %2, %3 Hz").arg(eff.width).arg(eff.height).arg(root.hz(eff.refresh)) + " · " + I18n.tr("custom"), mode: eff });
        return opts.sort((a, b) => b.mode.width * b.mode.height - a.mode.width * a.mode.height || b.mode.refresh - a.mode.refresh);
    }

    function value(name: string, key: string): var {
        const o = root.find(name);
        if (!o)
            return undefined;
        const c = root.effective(o);
        switch (key) {
        case "enabled":
            return c.enabled;
        case "mode":
            return root.modeKey(c.mode);
        case "customMode":
            return c.mode?.custom ? `${c.mode.width}x${c.mode.height}@${root.hz(c.mode.refresh)}` : "";
        case "scale":
            return c.scale;
        case "transform":
            return c.transform;
        }
        return undefined;
    }

    // Edits one output; a size change pushes the outputs right of / below
    // it along, so side-by-side layouts stay touching.
    function set(name: string, key: string, v: var): void {
        const o = root.find(name);
        if (!o)
            return;
        const before = root.effective(o);
        const next = Object.assign({}, before);
        switch (key) {
        case "enabled":
            next.enabled = !!v;
            if (next.enabled && !before.enabled) {
                const right = root.layout().reduce((m, r) => Math.max(m, r.x + r.w), 0);
                next.x = right;
                next.y = 0;
            }
            break;
        case "mode": {
            const opt = root.modeOptions(name).find(x => x.value === v);
            if (!opt)
                return;
            next.mode = opt.mode;
            break;
        }
        case "customMode": {
            const t = String(v).trim();
            if (t === "") {
                next.mode = root.liveCfg(o).mode;
                break;
            }
            const m = /^(\d+)\s*[x×]\s*(\d+)(?:\s*@\s*([\d.]+))?$/.exec(t);
            if (!m)
                return;
            next.mode = { width: +m[1], height: +m[2], refresh: m[3] ? +m[3] : 60, custom: true };
            break;
        }
        case "scale":
            next.scale = Math.max(0.25, Math.min(4, Number(v)));
            break;
        case "transform":
            next.transform = String(v);
            break;
        }
        const edits = { [name]: next };
        if (next.enabled && before.enabled) {
            const a = root.sizeOf(before), b = root.sizeOf(next);
            const dw = b.w - a.w, dh = b.h - a.h;
            if (dw !== 0 || dh !== 0)
                for (const other of root.outputs) {
                    if (other.name === name)
                        continue;
                    const c = root.effective(other);
                    const moved = Object.assign({}, c);
                    if (c.x >= before.x + a.w)
                        moved.x += dw;
                    if (c.y >= before.y + a.h)
                        moved.y += dh;
                    if (moved.x !== c.x || moved.y !== c.y)
                        edits[other.name] = moved;
                }
        }
        root.stage(edits);
    }

    // Drops a dragged output at logical (lx, ly): snapped edge to edge to the
    // nearest free side of another output (aligned when within snap reach),
    // then the whole layout moved so it starts at 0,0.
    function place(name: string, lx: real, ly: real): void {
        const rects = root.layout();
        const me = rects.find(r => r.name === name);
        if (!me)
            return;
        const others = rects.filter(r => r.name !== name);
        let best = { x: Math.round(lx), y: Math.round(ly), d: Infinity };
        if (others.length === 0)
            best = { x: 0, y: 0, d: 0 };
        const overlaps = (x, y) => others.some(r => x < r.x + r.w && x + me.w > r.x && y < r.y + r.h && y + me.h > r.y);
        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        for (const r of others) {
            const reach = 0.08 * Math.max(r.w, r.h, me.w, me.h);
            const alignY = y => Math.abs(y - r.y) < reach ? r.y : Math.abs(y + me.h - r.y - r.h) < reach ? r.y + r.h - me.h : y;
            const alignX = x => Math.abs(x - r.x) < reach ? r.x : Math.abs(x + me.w - r.x - r.w) < reach ? r.x + r.w - me.w : x;
            const ys = alignY(clamp(Math.round(ly), r.y - me.h + 1, r.y + r.h - 1));
            const xs = alignX(clamp(Math.round(lx), r.x - me.w + 1, r.x + r.w - 1));
            for (const c of [{ x: r.x + r.w, y: ys }, { x: r.x - me.w, y: ys }, { x: xs, y: r.y + r.h }, { x: xs, y: r.y - me.h }]) {
                if (overlaps(c.x, c.y))
                    continue;
                const d = Math.hypot(c.x - lx, c.y - ly);
                if (d < best.d)
                    best = { x: c.x, y: c.y, d: d };
            }
        }
        const pos = {};
        for (const r of rects)
            pos[r.name] = r.name === name ? { x: best.x, y: best.y } : { x: r.x, y: r.y };
        const minX = Math.min(...Object.values(pos).map(p => p.x));
        const minY = Math.min(...Object.values(pos).map(p => p.y));
        const edits = {};
        for (const o of root.outputs) {
            const p = pos[o.name];
            if (p)
                edits[o.name] = Object.assign(root.effective(o), { x: p.x - minX, y: p.y - minY });
        }
        root.stage(edits);
    }

    // Full configs → pending, keeping only what differs from the live state.
    function stage(edits: var): void {
        const p = Object.assign({}, root.pending);
        for (const name in edits) {
            const o = root.find(name);
            if (!o)
                continue;
            const live = root.liveCfg(o);
            const c = edits[name];
            const diff = {};
            if (c.enabled !== live.enabled)
                diff.enabled = c.enabled;
            if (!root.sameMode(c.mode, live.mode))
                diff.mode = c.mode;
            if (Math.abs(c.scale - live.scale) >= 0.005)
                diff.scale = c.scale;
            if (c.transform !== live.transform)
                diff.transform = c.transform;
            if (c.x !== live.x || c.y !== live.y) {
                diff.x = c.x;
                diff.y = c.y;
            }
            if (Object.keys(diff).length > 0)
                p[name] = diff;
            else
                delete p[name];
        }
        root.pending = p;
        root.error = "";
    }

    function discard(): void {
        root.pending = {};
        root.error = "";
    }

    // ---- applying ----

    function argsFor(targets: var): var {
        const args = ["wlr-randr"];
        for (const t of targets) {
            const o = root.find(t.name);
            if (!o)
                continue;
            args.push("--output", t.name);
            if (!t.enabled) {
                args.push("--off");
                continue;
            }
            const live = root.liveCfg(o);
            if (!live.enabled)
                args.push("--on");
            if (t.mode && !(live.enabled && root.sameMode(live.mode, t.mode)))
                args.push(t.mode.custom || root.backend === "drift" ? "--custom-mode" : "--mode",
                    `${t.mode.width}x${t.mode.height}@${Number(t.mode.refresh).toFixed(3)}`);
            args.push("--scale", Number(t.scale).toFixed(4), "--transform", t.transform, "--pos", `${Math.round(t.x)},${Math.round(t.y)}`);
        }
        return args;
    }

    function run(targets: var, confirm: bool): void {
        if (applyProc.running)
            return;
        applyProc.confirm = confirm;
        applyProc.command = root.argsFor(targets);
        applyProc.running = true;
    }

    function apply(): void {
        if (!root.canApply)
            return;
        root.previous = root.outputs.map(o => root.liveCfg(o));
        root.applied = root.outputs.map(o => root.effective(o));
        root.pending = {};
        root.run(root.applied, true);
    }

    function keep(): void {
        if (!root.confirming)
            return;
        root.confirming = false;
        confirmTimer.stop();
        root.saveProfile(root.applied);
    }

    function revert(): void {
        if (!root.confirming)
            return;
        root.confirming = false;
        confirmTimer.stop();
        root.run(root.previous, false);
    }

    Process {
        id: applyProc
        property bool confirm: false
        stderr: StdioCollector {
            id: applyErr
        }
        onExited: code => {
            if (code !== 0) {
                root.error = applyErr.text.trim().split("\n").pop() || `wlr-randr ${code}`;
            } else if (applyProc.confirm) {
                root.confirmLeft = root.cfg.confirmSec ?? 15;
                root.confirming = true;
                confirmTimer.restart();
            }
            root.refresh();
        }
    }

    Timer {
        id: confirmTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmLeft -= 1;
            if (root.confirmLeft <= 0)
                root.revert();
        }
    }

    // ---- kept layouts ----

    function saveProfile(targets: var): void {
        const outs = {};
        for (const t of targets) {
            const o = root.find(t.name);
            if (o)
                outs[root.idOf(o)] = { enabled: t.enabled, mode: t.mode, scale: t.scale, transform: t.transform, x: t.x, y: t.y };
        }
        const p = Object.assign({}, root.profiles);
        p[root.setKey()] = { outputs: outs };
        root.profiles = p;
        root.save();
    }

    function forgetProfiles(): void {
        root.profiles = {};
        root.save();
    }

    function restore(): void {
        if (!(root.cfg.restore ?? true) || applyProc.running)
            return;
        const prof = root.profiles[root.setKey()];
        if (!prof)
            return;
        const targets = root.outputs.map(o => {
            const s = prof.outputs?.[root.idOf(o)];
            return s ? Object.assign({ name: o.name }, s) : root.liveCfg(o);
        });
        if (!targets.some(t => t.enabled))
            return;
        if (targets.every((t, i) => root.sameCfg(t, root.liveCfg(root.outputs[i]))))
            return;
        root.run(targets, false);
    }

    // IPC `displays`: state (JSON), set <output> <key> <value> (the same
    // keys as the settings rows), place <output> <x> <y>, apply / keep /
    // revert / discard.
    IpcHandler {
        target: "displays"

        function state(): string {
            return JSON.stringify({ available: root.available, layout: root.layout(), pending: root.pending, confirming: root.confirming, confirmLeft: root.confirmLeft, error: root.error, setKey: root.setKey(), saved: Object.keys(root.profiles) });
        }
        function set(output: string, key: string, value: string): void {
            root.set(output, key, key === "enabled" ? value === "true" : key === "scale" ? Number(value) : value);
        }
        function place(output: string, x: string, y: string): void {
            root.place(output, Number(x), Number(y));
        }
        function apply(): void {
            root.apply();
        }
        function keep(): void {
            root.keep();
        }
        function revert(): void {
            root.revert();
        }
        function discard(): void {
            root.discard();
        }
    }

    function save(): void {
        stateFile.setText(JSON.stringify({ version: 1, profiles: root.profiles }, null, 2));
    }

    FileView {
        id: stateFile
        path: Quickshell.statePath("displays.json")
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(stateFile.text());
                root.profiles = (s.profiles && typeof s.profiles === "object") ? s.profiles : {};
            } catch (e) {
                console.warn("[displays] bad state file, starting empty:", e);
            }
        }
    }
}
