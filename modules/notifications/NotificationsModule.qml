import QtQuick
import "../../components"
import "center"

// Two modes in one module (spec): "flow" replaces the bar content with a single
// incoming notification; "center" is the history browser (iOS-style grouped
// list, mini-games when empty — see center/NotificationCenter.qml).
Item {
    id: root
    required property var payload
    required property var notificationsService
    required property var cfg
    property var theme
    signal closeRequested

    readonly property bool centerMode: (root.payload?.mode ?? "") === "center"
    readonly property var item: root.payload?.notification ?? null
    // Content-fitted island height (center only; -1 = use the config size).
    readonly property real preferredHeight: root.centerMode ? (center.item?.preferredHeight ?? -1) : -1

    // Shared-element slots (core/TransitionLayer): flow card's arrival time.
    function sharedSlot(key: string): var {
        return (key === "time" && !root.centerMode) ? flowCard.timeSlot : null;
    }

    // ── Flow mode: the incoming notification ──
    NotificationCard {
        id: flowCard
        anchors.fill: parent
        anchors.margins: 14
        visible: !root.centerMode
        notif: root.item
        cfg: root.cfg
    }

    // ── Center mode ──
    Loader {
        id: center
        anchors.fill: parent
        active: root.centerMode
        sourceComponent: NotificationCenter {
            service: root.notificationsService
            cfg: root.cfg
            theme: root.theme
            onCloseRequested: root.closeRequested()
        }
    }
}
