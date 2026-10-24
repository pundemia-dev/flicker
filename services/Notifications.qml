import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "../config"
import "NotificationRules.js" as Rules

Item {
    id: root

    signal notificationReceived(var notif)
    // An entry left the history (sender closed it, it expired, or it was
    // trimmed): drop it from queues/views — the object is freed after destroyDelay.
    signal notificationClosed(var notif)
    // Toasts taken back before they show (their app was just muted):
    // islands drop them from their queues.
    signal toastsWithdrawn(var entries)
    property var history: []
    // Shown but not stored (low urgency with historyLowUrgency off, a rule's
    // history off): released once every target island is done with its
    // toast (toastClosed counts entry.toastViews down); transientMs only
    // guards against a leak.
    property var transients: []
    readonly property int transientMs: 1800000
    // Injected (Shell): the focused output, for notifications.screens.
    property var compositor: null
    property bool doNotDisturb: false
    // Injected (Shell): a PipeWire screencast or our own recording =
    // "sharing" (DND by itself, toast text hidden — see Config).
    property var privacy: null
    property var recorder: null

    readonly property var cfg: Config.data.notifications
    readonly property bool sharing: (root.privacy?.screenNodes?.length ?? 0) > 0 || !!root.recorder?.recording
    readonly property bool autoQuiet: (root.cfg.dndWhileSharing ?? true) && root.sharing
    // Effective Do Not Disturb: the switch, or sharing.
    readonly property bool quiet: root.doNotDisturb || root.autoQuiet
    // Toasts show the app name only (notifications.privacy).
    readonly property bool redact: {
        const p = root.cfg.privacy ?? "sharing";
        return p === "always" || p === "sharing" && root.sharing;
    }
    // Mini-games of the empty Notification Center: last picked game and
    // best scores survive closing the center (session only).
    property string lastGame: ""
    property var gameBest: ({})
    // Grace period before a dropped entry object is freed (> swap fade-out).
    readonly property int destroyDelay: 1500

    Component.onCompleted: {
        // Kick the async .desktop scan early so the icon fallback below is
        // ready before the first notifications arrive.
        DesktopEntries.applications?.values;
        Qt.callLater(root.ensureRuleIds);
    }

    // App icon fallback for senders with an empty app_icon (e.g. Telegram
    // Desktop sends avatars but no icon): match the notification's appName
    // against installed .desktop entries (exact Name/id hit, then a
    // reverse-domain suffix hit like "org.telegram.desktop" for
    // "Telegram Desktop", then the exec basename).
    function desktopIconFor(appName) {
        const flat = s => (s ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
        const target = flat(appName);
        if (!target)
            return "";
        const apps = DesktopEntries.applications?.values ?? [];
        // NOTE: DesktopEntry.id has no ".desktop" suffix ("org.telegram.desktop"
        // is the app id, not a filename) — do NOT strip it.
        const key = a => flat(a.id ?? "");
        const execBase = a => {
            // DesktopEntry.command is a string LIST ("prog,arg,..." when
            // coerced) — take the first element's basename.
            const first = String(a.command ?? "").split(",")[0].trim().split(" ")[0] ?? "";
            return flat(first.split("/").pop());
        };
        const hit = apps.find(a => flat(a.name) === target && a.icon)
            ?? apps.find(a => key(a) === target && a.icon)
            ?? apps.find(a => key(a).endsWith(target) && a.icon)
            ?? apps.find(a => execBase(a) === target && a.icon);
        return hit?.icon ?? "";
    }

    // Icon/avatar resolution for a server-side Notification (re-run by each
    // NotificationEntry whenever its source updates in place).
    function resolveIcons(notif) {
        let appIcon = notif.appIcon;
        let image = notif.image;
        if (!appIcon && image) {
            // Some senders (notify-send 0.8.x puts --icon there, leaving
            // app_icon empty) smuggle a themed icon NAME through the
            // image-path hint, which Quickshell exposes as
            // "image://icon/<name>". A bare name (no "/") is an icon, not
            // a picture — route it to the app icon so the card doesn't
            // render a broken avatar. File/URL values always contain "/".
            const prefix = "image://icon/";
            const bare = image.startsWith(prefix) ? image.slice(prefix.length) : image;
            if (bare.length > 0 && !bare.includes("/")) {
                appIcon = bare;
                image = "";
            }
        }
        if (!appIcon)
            appIcon = root.desktopIconFor(notif.appName);
        // `image` = sender avatar / picture (messengers put the chat avatar
        // here via image-data / image-path hints). Empty when the app sends
        // none — the card then falls back to the app icon.
        return { appIcon: appIcon, image: image };
    }

    // Drops an entry from history (closed by the sender, expired, or pushed
    // out past historyLimit). Listeners (Island queue, center view) get
    // notificationClosed first; the entry object is destroyed only after
    // destroyDelay, so a card still fading out (ContentSwap keeps the old
    // content ~0.35s) never renders a dead object.
    function forget(entry) {
        if (!root.history.includes(entry) && !root.transients.includes(entry))
            return;
        root.history = root.history.filter(e => e !== entry);
        root.transients = root.transients.filter(e => e !== entry);
        root.notificationClosed(entry);
        entry.destroy(root.destroyDelay);
    }

    // Dismisses every entry of a list (group / "clear all"); copies first:
    // each dismissal shrinks history synchronously via forget().
    function dismissAll(entries) {
        for (const e of [...entries])
            e.dismiss();
    }

    function suppressed(notif): bool {
        const fields = { app: notif.appName ?? "", summary: notif.summary ?? "", body: notif.body ?? "" };
        for (const rule of Config.data.notifications.suppress ?? []) {
            const keys = Object.keys(rule).filter(k => k in fields);
            if (keys.length > 0 && keys.every(k => new RegExp(rule[k], "i").test(fields[k])))
                return true;
        }
        return false;
    }

    // ---- per-app rules (notifications.rules, see Config) ----

    function ruleLive(rule: var, now: double): bool {
        return Rules.live(rule, now);
    }

    // Empty pattern = any; a bad regex never matches (settings shows it).
    // Compiled rule patterns (null = invalid), rebuilt with the config.
    property var reCache: ({})
    // Own keys only: `in` also saw Object.prototype ("constructor" as a
    // pattern returned a function and every arrival threw).
    function compiled(pattern: string): var {
        if (!Object.prototype.hasOwnProperty.call(root.reCache, pattern))
            root.reCache[pattern] = Rules.compile(pattern);
        return root.reCache[pattern];
    }
    function matches(pattern: string, values: var): bool {
        if (!pattern)
            return true;
        const re = root.compiled(pattern);
        return !!re && values.some(v => re.test(v ?? ""));
    }

    // The first live rule matching (a rule without any condition matches
    // nothing).
    function ruleFor(notif: var): var {
        const now = Date.now();
        const urgency = ["low", "normal", "critical"][notif.urgency] ?? "normal";
        for (const rule of root.cfg.rules ?? []) {
            if (!root.ruleLive(rule, now) || !(rule.app || rule.text || rule.urgency))
                continue;
            if (rule.urgency && rule.urgency !== urgency)
                continue;
            if (root.matches(rule.app ?? "", [notif.appName, notif.desktopEntry])
                && root.matches(rule.text ?? "", [notif.summary, notif.body]))
                return rule;
        }
        return null;
    }

    // What an arrival may do: toast, sound, stay in history, pass Do Not
    // Disturb; durationMs = the rule's toast time (0 = default). Rules only
    // take away (but bypassDnd / durationMs).
    function policyFor(notif: var): var {
        const c = root.cfg;
        const low = notif.urgency === NotificationUrgency.Low;
        const rule = root.ruleFor(notif);
        const allow = key => rule?.[key] !== false;
        const p = {
            toast: !(low && (c.onlyUrgentToast ?? true)) && allow("toast"),
            sound: allow("sound"),
            history: !(low && !(c.historyLowUrgency ?? true)) && allow("history"),
            bypassDnd: rule?.bypassDnd === true || notif.urgency === NotificationUrgency.Critical && (c.dndAllowCritical ?? true),
            durationMs: rule?.durationMs ?? 0
        };
        if (root.quiet && !p.bypassDnd) {
            p.toast = false;
            p.sound = false;
        }
        return p;
    }

    // Rules carry a stable id (settings pages follow a rule by it while
    // mute / sweep reorder the list); hand-written ones get one here.
    function newRuleId(): string {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }
    onCfgChanged: {
        root.reCache = {};
        Qt.callLater(root.ensureRuleIds);
    }
    function ensureRuleIds(): void {
        const rules = root.cfg.rules ?? [];
        if (rules.every(r => !r || r.id))
            return;
        Config.set("notifications.rules", rules.map(r => r && !r.id ? Object.assign({ id: root.newRuleId() }, r) : r));
    }

    // "Mute" on a notification (NotificationActions): a rule for its app,
    // toast and sound off, until `span` ("hour" | "today" | "always") ends.
    // Muting a muted app again only moves its end.
    function mute(entry: var, span: string): void {
        const name = entry?.appName ?? "";
        if (name === "")
            return;
        const app = "^" + name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "$";
        const now = new Date();
        const until = span === "hour" ? now.getTime() + 3600000
            : span === "today" ? new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime() : 0;
        const rules = (root.cfg.rules ?? []).map(r => Object.assign({}, r));
        // The app's own rule (same app pattern, no other condition) is
        // reused whatever the user changed in it since.
        // It goes first: an earlier rule matching the app would win.
        const at = rules.findIndex(r => r.app === app && !r.text && !r.urgency);
        const rule = at >= 0 ? rules.splice(at, 1)[0] : { id: root.newRuleId(), name: name, app: app };
        Object.assign(rule, { enabled: true, toast: false, sound: false, until: until });
        rules.unshift(rule);
        Config.set("notifications.rules", rules);
        // Its toasts still waiting in the islands' queues go too (the
        // muted one itself closes with its panel).
        const waiting = [...root.history, ...root.transients].filter(e => e !== entry && e.appName === name && e.toastViews > 0);
        if (waiting.length > 0)
            root.toastsWithdrawn(waiting);
    }

    // Toast lifetime (ms) of an entry; 0 = until dismissed. `queued` = more
    // wait behind it (shorter, but never for an until-dismissed one).
    // A rule's time or the sender's own (appTimeout) is kept as asked;
    // only the urgency defaults shorten while more are queued.
    function toastMs(entry: var, queued: bool): int {
        const c = root.cfg;
        let ms = entry?.policy?.durationMs ?? 0;
        if (ms <= 0 && (c.appTimeout ?? false))
            ms = entry?.appTimeoutMs ?? 0;
        if (ms > 0)
            return ms;
        const u = entry?.urgency ?? NotificationUrgency.Normal;
        ms = u === NotificationUrgency.Critical ? (c.flowShowCriticalMs ?? 10000)
            : u === NotificationUrgency.Low ? (c.flowShowLowMs ?? 3000) : (c.flowShowMs ?? 5000);
        if (ms <= 0)
            return 0;
        return queued ? Math.min(ms, c.flowShowQueuedMs ?? 3000) : ms;
    }

    // Outputs that show a toast (notifications.screens), decided once per
    // arrival. Focus not known yet = the first output; nothing left to
    // show on = the focused one, so a toast is never silently lost.
    function toastScreens(): var {
        const mode = root.cfg.screens ?? "all";
        const list = root.cfg.screenList ?? [];
        const names = Quickshell.screens.map(s => s.name);
        const reported = root.compositor?.focusedOutput ?? "";
        const focused = names.includes(reported) ? reported : (names[0] ?? "");
        let targets = mode === "focused" ? [focused]
            : mode === "only" ? list : mode === "except" ? names.filter(n => !list.includes(n)) : names;
        targets = targets.filter(n => names.includes(n));
        if (targets.length === 0 && focused !== "")
            targets = [focused];
        return targets;
    }

    // One target island is done with an entry's toast (shown and gone,
    // or the island went away): toastViews > 0 = still on screen or
    // queued somewhere (dedupe reads it); a transient one is released
    // after the last.
    function toastClosed(entry: var): void {
        if (!entry || entry.toastViews <= 0)
            return;
        entry.toastViews -= 1;
        if (entry.toastViews <= 0 && root.transients.includes(entry))
            entry.release();
    }

    // One-time code in a login / 2FA message ("Copy 123456"): of the 4–8
    // digit numbers (or 123-456), the one nearest a code-ish word ("Order
    // 98765 shipped. Your code is 4321" = 4321).
    function codeOf(summary: string, body: string): string {
        if (!(root.cfg.codeCopy ?? true))
            return "";
        const text = `${summary} ${body}`.replace(/<[^>]*>/g, " ");
        const words = [];
        const wordRe = /\b(code|otp|pin|passcode|password|verification|2fa)\b|код|парол|подтвержд|одноразов/gi;
        for (let m = wordRe.exec(text); m; m = wordRe.exec(text))
            words.push({ from: m.index, to: m.index + m[0].length });
        if (words.length === 0)
            return "";
        let best = "";
        let bestGap = Infinity;
        const numRe = /(?:^|[^\w-])(\d{3}[- ]\d{3}|\d{4,8})(?![\w-])/g;
        for (let m = numRe.exec(text); m; m = numRe.exec(text)) {
            const from = m.index + m[0].length - m[1].length;
            const to = from + m[1].length;
            const gap = Math.min(...words.map(w => w.to <= from ? from - w.to : w.from >= to ? w.from - to : 0));
            if (gap < bestGap) {
                bestGap = gap;
                best = m[1];
            }
        }
        return best.replace(/[- ]/g, "");
    }

    // Same app + title + text as an entry already in the history.
    function duplicateOf(notif: var): var {
        if (!(root.cfg.dedupe ?? true))
            return null;
        return [...root.history, ...root.transients].find(e => e.appName === notif.appName && e.summary === notif.summary && e.body === notif.body) ?? null;
    }

    // Housekeeping once a minute while there is any: expired timed rules
    // leave the config, history past historyMaxAgeHours and forgotten
    // transients are released.
    readonly property bool timedRules: (root.cfg.rules ?? []).some(r => (r?.until ?? 0) > 0)
    Timer {
        interval: 60000
        repeat: true
        running: root.timedRules || (root.cfg.historyMaxAgeHours ?? 0) > 0 || root.transients.length > 0
        onTriggered: root.sweep()
    }
    function sweep(): void {
        const now = Date.now();
        const rules = root.cfg.rules ?? [];
        const kept = rules.filter(r => !Rules.expired(r, now));
        if (kept.length !== rules.length)
            Config.set("notifications.rules", kept);
        // Never one still on screen / queued (toastViews > 0).
        const hours = root.cfg.historyMaxAgeHours ?? 0;
        const old = hours > 0 ? root.history.filter(e => e.toastViews <= 0 && now - e.time > hours * 3600000) : [];
        const stale = root.transients.filter(e => e.toastViews <= 0 && now - e.time > root.transientMs);
        for (const e of [...old, ...stale])
            e.release();
    }

    AppActivator {
        id: activator
        launchPrefix: Config.data.launcher?.apps?.launchPrefix ?? []
    }

    // Tap on a notification (iOS): the sender's default action (Telegram
    // opens that chat), then its window is focused — or the app started
    // when it has no window and no default action.
    function open(entry: var): void {
        if (!entry)
            return;
        // Read before invoking: the sender may close the notification.
        const names = [entry.desktopEntry, entry.appName].filter(n => (n ?? "") !== "");
        const handled = entry.invokeDefault();
        if (!activator.activate(names)) {
            if (handled)
                activator.activateSoon(names);
            else
                activator.launch(names);
        }
        // Opened = read: out of the history (non-resident senders already
        // closed it by invoking).
        if (root.history.includes(entry))
            entry.dismiss();
    }

    Component {
        id: entryComp
        NotificationEntry {}
    }

    NotificationServer {
        keepOnReload: false
        persistenceSupported: true
        bodyMarkupSupported: true
        // Senders only attach actions / an inline reply when the server
        // advertises them (Telegram checks at its start).
        actionsSupported: true
        inlineReplySupported: true
        imageSupported: true
        onNotification: notif => {
            // notifications.suppress: duplicates of what an event indicator
            // already shows (blueman "Connected") never become a card.
            if (root.suppressed(notif)) {
                notif.dismiss();
                return;
            }
            // A repeat while the copy we have is still on screen / queued
            // is merged into it (dropped); a critical one always comes
            // through. Later repeats replace the copy (below).
            const dup = root.duplicateOf(notif);
            if (dup && dup.toastViews > 0 && notif.urgency !== NotificationUrgency.Critical) {
                // Closed as expired: the user never saw or touched it.
                notif.expire();
                return;
            }
            const policy = root.policyFor(notif);
            // Toast only where notifications.screens says (none = no toast).
            const screens = policy.toast ? root.toastScreens() : [];
            if (screens.length === 0)
                policy.toast = false;
            // Nowhere to go (no toast, not stored): closed as expired.
            if (!policy.toast && !policy.history) {
                notif.expire();
                return;
            }
            // Keep the server-side object alive: image-data pictures are
            // exposed as session-local "image://qsimage/…" URLs that die
            // with the notification (pShell pattern). Every tracked object
            // is released again: on close (forget) or when trimmed below.
            // `replaces_id` updates arrive IN PLACE on the same object
            // (no new onNotification) and the entry mirrors them live.
            notif.tracked = true;
            const entry = entryComp.createObject(root, {
                notification: notif,
                resolve: root.resolveIcons,
                service: root,
                policy: policy,
                toastScreens: screens,
                toastViews: screens.length
            });
            entry.closed.connect(() => root.forget(entry));
            // A later repeat replaces the older copy (closed -> forget).
            if (dup)
                dup.release();
            if (!policy.history) {
                root.transients = [...root.transients, entry];
                if (policy.sound)
                    root.playSound(notif);
                root.notificationReceived(entry);
                return;
            }

            // Newest first, capped (feeds the Notification Center history).
            // Entries past the cap are expired server-side: the sender gets
            // NotificationClosed and the object is freed (was a leak).
            const limit = Config.data.notifications.historyLimit;
            const next = [entry, ...root.history];
            root.history = next.slice(0, limit);
            for (const old of next.slice(limit))
                old.release(); // -> closed -> forget (already out of history)
            for (const old of next.slice(limit)) {
                root.notificationClosed(old);
                old.destroy(root.destroyDelay);
            }
            if (policy.sound)
                root.playSound(notif);
            if (policy.toast)
                root.notificationReceived(entry);
        }
    }

    // New-notification sound (notifications.sound*); the caller already
    // skips Do Not Disturb and rules. A burst plays once: a sound still playing
    // swallows the next.
    function playSound(notif: var): void {
        const cfg = root.cfg;
        const hints = notif.hints ?? {};
        if (!cfg.sound || hints["suppress-sound"] || soundProc.running)
            return;
        if (notif.urgency === NotificationUrgency.Low && !cfg.soundLowUrgency)
            return;
        const file = `${hints["sound-file"] || cfg.soundFile || ""}`.replace(/^file:\/\//, "");
        if (!file)
            return;
        // audio.eventVolume: the QS audio panel's "System sounds" slider.
        const volume = Config.data.audio.eventVolume ?? 1;
        if (volume <= 0)
            return;
        soundProc.command = ["pw-play", `--volume=${volume}`, file];
        soundProc.running = true;
    }
    Process {
        id: soundProc
    }
}
