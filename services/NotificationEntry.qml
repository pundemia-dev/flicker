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
    }
}
