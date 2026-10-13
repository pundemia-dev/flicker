import QtQuick
import Quickshell.Services.Notifications

// One history entry (pShell Notif pattern): a live mirror of the tracked
// server-side Notification. Quickshell applies `replaces_id` updates IN
// PLACE on the same object (no second onNotification), so the fields follow
// its change signals — a plain snapshot went stale on every update.
// `closed` fires when the sender closes it, it expires, or we dismiss it.
QtObject {
    id: entry

    property Notification notification: null
    // Icon/image resolver from the service (fallback chain, see
    // Notifications.resolveIcons) — re-run whenever the source changes.
    property var resolve: null
    signal closed

    property string appName: ""
    property string appIcon: ""
    property string image: ""
    property string summary: ""
    property string body: ""
    property int urgency: NotificationUrgency.Normal
    // Sender actions shown as context buttons ({id, text}); "default" (=
    // tap) and "inline-reply" (= the reply field) are not buttons.
    property var actions: []
    property bool hasDefault: false
    // Inline reply (KDE extension, Telegram Desktop uses it when the
    // server advertises "inline-reply").
    property bool canReply: false
    property string replyPlaceholder: ""
    // desktop-entry hint (app id without ".desktop"), for focusing / launching.
    property string desktopEntry: ""
    // Arrival time; bumped on in-place replacement (it is a fresh message).
    property double time: Date.now()

    function sync(): void {
        const n = entry.notification;
        if (!n)
            return;
        const icons = entry.resolve ? entry.resolve(n) : ({ appIcon: n.appIcon, image: n.image });
        entry.appName = n.appName;
        entry.appIcon = icons.appIcon;
        entry.image = icons.image;
        entry.summary = n.summary;
        entry.body = n.body;
        entry.urgency = n.urgency;
        const all = n.actions ?? [];
        entry.hasDefault = all.some(a => a.identifier === "default");
        entry.actions = all.filter(a => a.identifier !== "default" && a.identifier !== "inline-reply" && (a.text ?? "") !== "")
            .map(a => ({ id: a.identifier, text: a.text }));
        entry.canReply = n.hasInlineReply;
        entry.replyPlaceholder = n.inlineReplyPlaceholder ?? "";
        entry.desktopEntry = n.desktopEntry ?? "";
    }

    // Closes the server-side notification (sender gets NotificationClosed).
    function release(): void {
        entry.notification?.expire();
    }

    // User dismissal from the Notification Center (sender gets
    // NotificationClosed(Dismissed); `closed` then drops the entry).
    function dismiss(): void {
        entry.notification?.dismiss();
    }

    // Activates the sender's "default" action (iOS tap = open the app).
    // Returns false when the sender declared none.
    function invokeDefault(): bool {
        const action = (entry.notification?.actions ?? []).find(a => a.identifier === "default");
        if (!action)
            return false;
        action.invoke();
        return true;
    }

    // Context button: runs the sender's action by identifier.
    function invoke(id: string): bool {
        const action = (entry.notification?.actions ?? []).find(a => a.identifier === id);
        if (!action)
            return false;
        action.invoke();
        return true;
    }

    // Answers in place (the sender gets NotificationReplied); the app is
    // never focused.
    function reply(text: string): bool {
        if (!entry.canReply || !entry.notification || text.trim() === "")
            return false;
        entry.notification.sendInlineReply(text);
        return true;
    }

    Component.onCompleted: sync()

    property Connections conn: Connections {
        target: entry.notification
        function onClosed(): void { entry.closed(); }
        function onSummaryChanged(): void { entry.sync(); entry.time = Date.now(); }
        function onBodyChanged(): void { entry.sync(); entry.time = Date.now(); }
        function onAppNameChanged(): void { entry.sync(); }
        function onAppIconChanged(): void { entry.sync(); }
        function onImageChanged(): void { entry.sync(); }
        function onUrgencyChanged(): void { entry.sync(); }
        function onActionsChanged(): void { entry.sync(); }
        function onHasInlineReplyChanged(): void { entry.sync(); }
        function onInlineReplyPlaceholderChanged(): void { entry.sync(); }
        function onDesktopEntryChanged(): void { entry.sync(); }
    }
}
