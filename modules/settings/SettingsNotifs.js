.pragma library
.import "../../services/NotificationRules.js" as Rules

// Notifications section helpers: the per-app rule list (Config
// `notifications.rules`, matched by Notifications.ruleFor) as generated
// rows and the drill-down page of one rule. Refs work like the VPN rules'
// (SettingsVpn.js) plus the rule's `id` ({ index, id, list }): the
// service adds / removes rules on its own (mute, expiry), so the page finds
// its rule by id (SettingsWindow.refIndex); a deleted rule's ref keeps a
// copy (`gone`, index -1).

const LIST = "notifications.rules";
const S = 1000;

// A missing field reads as this (a rule only stores what differs).
const DEFAULTS = { enabled: true, app: "", text: "", urgency: "", toast: true, sound: true, history: true, bypassDnd: false, durationMs: 0, until: 0 };

const URGENCIES = [
    { value: "", label: "Any" },
    { value: "low", label: "Low only" },
    { value: "normal", label: "Normal only" },
    { value: "critical", label: "Critical only" }
];

function field(rule, key) {
    return rule?.[key] ?? DEFAULTS[key];
}

function expired(rule, now) {
    return Rules.expired(rule, now);
}

function isEmpty(rule) {
    return !`${rule?.app ?? ""}`.trim() && !`${rule?.text ?? ""}`.trim() && !rule?.urgency;
}

// "" or the translated error: a pattern Notifications.matches would skip.
function ruleError(rule, tr) {
    for (const [key, name] of [["app", "App"], ["text", "Text"]]) {
        const v = `${rule?.[key] ?? ""}`;
        if (v === "")
            continue;
        if (!Rules.compile(v))
            return tr("%1: bad regular expression").arg(tr(name));
    }
    return "";
}

function clock(ms) {
    const d = new Date(ms);
    const pad = n => String(n).padStart(2, "0");
    const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    const today = new Date();
    return d.toDateString() === today.toDateString() ? hm : `${pad(d.getDate())}.${pad(d.getMonth() + 1)} ${hm}`;
}

// What the rule does, for the list (translated).
function effect(rule, tr) {
    const toast = field(rule, "toast");
    const sound = field(rule, "sound");
    const history = field(rule, "history");
    let s;
    if (!toast && !history)
        s = tr("Ignored");
    else if (!toast && !sound)
        s = tr("Muted");
    else if (!toast)
        s = tr("No toast");
    else if (!sound)
        s = tr("Silent");
    else if (!history)
        s = tr("Not saved");
    else if (field(rule, "bypassDnd"))
        s = tr("Through DND");
    else if (field(rule, "durationMs") > 0)
        s = tr("%1 s").arg(Math.round(rule.durationMs / S));
    else
        s = tr("No change");
    return (rule?.until ?? 0) > 0 ? tr("%1 until %2").arg(s).arg(clock(rule.until)) : s;
}

// The list row label: the rule's name, else its patterns.
function summary(rule, tr) {
    const name = `${rule.name ?? ""}`.trim();
    if (name !== "")
        return name;
    const parts = [rule.app, rule.text].map(v => `${v ?? ""}`.trim()).filter(v => v !== "");
    if (parts.length > 0)
        return parts.join(" · ");
    return rule.urgency ? tr(URGENCIES.find(u => u.value === rule.urgency)?.label ?? "") : tr("No conditions");
}

function rulePage(ref) {
    const row = (key, extra) => Object.assign({ store: "notifRule", ref: ref, key: key }, extra);
    return {
        title: "Rule",
        ruleRef: ref,
        groups: [
            { rows: [
                row("name", { label: "Name", kind: "text", allowEmpty: true, placeholder: "Optional" }),
                row("enabled", { label: "Enabled", kind: "bool" })
            ] },
            { title: "When", footerFrom: "notifRule", ref: ref, footer: "Case-insensitive regular expressions: App matches the app name or its desktop entry, Text the title or the message. Rules are tried top to bottom; the first one that matches decides. A rule without conditions is removed.", rows: [
                row("app", { label: "App", kind: "text", wide: true, allowEmpty: true, placeholder: "telegram|discord" }),
                row("text", { label: "Text", kind: "text", wide: true, allowEmpty: true, placeholder: "Optional" }),
                row("urgency", { label: "Urgency", kind: "choice", options: URGENCIES })
            ] },
            { title: "Then", footer: "Off = never: a notification with neither a toast nor history is dropped. Through Do Not Disturb also lets its sound play.", rows: [
                row("toast", { label: "Toast", kind: "bool" }),
                row("sound", { label: "Sound", kind: "bool" }),
                row("history", { label: "Keep in Notification Center", kind: "bool" }),
                row("bypassDnd", { label: "Through Do Not Disturb", kind: "bool" }),
                row("durationMs", { label: "Show toast for", kind: "number", min: 0, max: 60000, step: 1000, scale: S, suffix: " s", zeroLabel: "Default" })
            ] },
            { footerFrom: "notifRuleUntil", ref: ref, rows: [
                { kind: "action", label: "Keep after it expires", action: "notifRuleForever", ref: ref },
                { kind: "action", label: "Move up", action: "ruleUp", ref: ref },
                { kind: "action", label: "Move down", action: "ruleDown", ref: ref },
                { kind: "action", label: "Delete rule", action: "ruleDelete", ref: ref, destructive: true, confirm: "Tap again to delete" }
            ] }
        ]
    };
}

// The generated group: one row per rule (opens its page), then "Add rule".
function rulesGroup(group, rules, tr) {
    const now = Date.now();
    const rows = rules.map(r => r ?? {}).map((r, i) => ({
        kind: "page",
        label: summary(r, tr),
        detail: ruleError(r, tr) ? tr("Invalid") : effect(r, tr),
        muted: r.enabled === false || expired(r, now),
        page: rulePage({ index: i, id: r.id, list: LIST })
    }));
    rows.push({ kind: "action", label: "Add rule", action: "notifRuleAdd" });
    return Object.assign({}, group, { rows: rows });
}
