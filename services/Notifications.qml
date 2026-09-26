import QtQuick
import Quickshell.Services.Notifications
import "../config"

Item {
    id: root

    signal notificationReceived(var notif)
    property var history: []
    property bool doNotDisturb: false

    NotificationServer {
        keepOnReload: false
        persistenceSupported: true
        bodyMarkupSupported: true
        onNotification: notif => {
            const wrapped = {
                id: notif.id,
                appName: notif.appName,
                summary: notif.summary,
                body: notif.body,
                urgency: notif.urgency,
                time: Date.now()
            };
            // Newest first, capped (feeds the Notification Center history).
            root.history = [wrapped, ...root.history].slice(0, Config.data.notifications.historyLimit);
            if (!root.doNotDisturb)
                root.notificationReceived(wrapped);
        }
    }
}
