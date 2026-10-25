.pragma library

// Displays section helpers (services/Displays): the arrangement group (the
// SettingsDisplays widget), the list of outputs, one output's page, and the
// Apply / Keep group shown while there is something to apply or confirm.
// Output rows carry a `ref` { name } and store "display" (SettingsWindow.
// valueOf / setValue → Displays.value / set); a page's groups are generated
// (`generate: "displayOutput"`) so they follow the output and its edits.

const TRANSFORMS = [
    { value: "normal", label: "Standard" },
    { value: "90", label: "90°" },
    { value: "180", label: "180°" },
    { value: "270", label: "270°" },
    { value: "flipped", label: "Flipped" },
    { value: "flipped-90", label: "Flipped, 90°" },
    { value: "flipped-180", label: "Flipped, 180°" },
    { value: "flipped-270", label: "Flipped, 270°" }
];

function summary(d, o, tr) {
    const c = d.effective(o);
    if (!c.enabled)
        return tr("Off");
    const sz = d.sizeOf(c);
    return `${sz.w} × ${sz.h} · ${Math.round(c.scale * 100)} %`;
}

function page(d, o) {
    return { title: d.label(o), groups: [{ generate: "displayOutput", ref: { name: o.name }, rows: [] }] };
}

function arrangementGroup(group, d) {
    return Object.assign({}, group, { widget: d.available && d.outputs.length > 0 ? "displays" : "", rows: [] });
}

function listGroup(group, d, tr) {
    const rows = d.outputs.map(o => ({
        kind: "page",
        label: d.label(o),
        detail: summary(d, o, tr),
        muted: !d.effective(o).enabled,
        page: page(d, o)
    }));
    if (rows.length === 0)
        rows.push({ kind: "action", label: d.available ? "No displays" : "wlr-randr is not installed", action: "displayNone" });
    return Object.assign({}, group, { rows: rows });
}

// Apply / Discard while edits wait; Keep / Revert while a change waits for
// its confirmation. Nothing otherwise.
function applyGroups(d) {
    if (d.confirming)
        return [{ footer: "The displays go back to how they were unless you keep the change.", rows: [
            { kind: "action", label: "Keep changes", action: "displayKeep" },
            { kind: "action", label: "Revert", action: "displayRevert", destructive: true }
        ] }];
    if (d.hasPending)
        return [{ footerFrom: "displayApply", rows: [
            { kind: "action", label: "Apply", action: "displayApply" },
            { kind: "action", label: "Discard changes", action: "displayDiscard" }
        ] }];
    return [];
}

function outputGroups(ref, d, tr) {
    const o = d.find(ref.name);
    if (!o)
        return [{ rows: [{ kind: "action", label: "Not connected", action: "displayNone" }] }];
    const row = (key, extra) => Object.assign({ store: "display", ref: ref, key: key }, extra);
    const c = d.effective(o);
    const sz = d.sizeOf(c);
    const groups = [{ rows: [row("enabled", { label: "Use this display", kind: "bool" })] }];
    if (c.enabled) {
        groups.push({
            footer: tr("Looks like %1 × %2. A custom resolution is one the display does not list (WIDTHxHEIGHT@Hz): the picture is scaled.").arg(sz.w).arg(sz.h),
            rows: [
                row("mode", { label: "Resolution", kind: "choice", optionsFrom: "displayModes" }),
                row("customMode", { label: "Custom", kind: "text", allowEmpty: true, placeholder: "2458x1536@60" }),
                row("scale", { label: "Scale", kind: "number", min: 0.5, max: 3, step: 0.05, scale: 0.01, suffix: " %" }),
                row("transform", { label: "Rotation", kind: "choice", options: TRANSFORMS })
            ]
        });
    }
    return groups.concat(applyGroups(d));
}
