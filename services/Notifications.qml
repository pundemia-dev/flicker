import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../config"

Item {
    id: root

    signal notificationReceived(var notif)
    // An entry left the history (sender closed it, it expired, or it was
    // trimmed): drop it from queues/views — the object is freed after destroyDelay.
    signal notificationClosed(var notif)
    property var history: []
    property bool doNotDisturb: false
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
        if (!root.history.includes(entry))
            return;
        root.history = root.history.filter(e => e !== entry);
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

    Component {
        id: entryComp
        NotificationEntry {}
    }

    NotificationServer {
        keepOnReload: false
        persistenceSupported: true
        bodyMarkupSupported: true
        onNotification: notif => {
            // notifications.suppress: duplicates of what an event indicator
            // already shows (blueman "Connected") never become a card.
            if (root.suppressed(notif)) {
                notif.dismiss();
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
                resolve: root.resolveIcons
            });
            entry.closed.connect(() => root.forget(entry));
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
            if (!root.doNotDisturb)
                root.notificationReceived(entry);
        }
    }
}
