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
    property var frost: null
    // Island height of the plain flow card (config modules["notifications:flow"]).
    property real flowHeight: 90
    signal closeRequested

    readonly property bool centerMode: (root.payload?.mode ?? "") === "center"
    readonly property var knockouts: root.centerMode ? (center.item?.knockouts ?? []) : []
    readonly property var item: root.payload?.notification ?? null
    // Content-fitted island height: the center's list, the flow card + its
    // context panel.
    readonly property real preferredHeight: root.centerMode ? (center.item?.preferredHeight ?? -1) : flowCard.preferredHeight
    // Reply field (flow card / center tile) needs the keyboard; the flow
    // auto-close waits while in use.
    readonly property bool wantsKeyboard: root.centerMode ? (center.item?.wantsKeyboard ?? false) : flowCard.wantsKeyboard
    readonly property bool holdOpen: !root.centerMode && flowCard.holdOpen

    // Shared-element slots (core/TransitionLayer): flow card's arrival time.
    function sharedSlot(key: string): var {
        return (key === "time" && !root.centerMode) ? flowCard.timeSlot : null;
    }

    // ── Flow mode: the incoming notification ──
    FlowCard {
        id: flowCard
        anchors.fill: parent
        visible: !root.centerMode
        enabled: !root.centerMode
        entry: root.item
        service: root.notificationsService
        cfg: root.cfg
        theme: root.theme
        baseHeight: root.flowHeight
        onCloseRequested: root.closeRequested()
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
            frost: root.frost
            onCloseRequested: root.closeRequested()
        }
    }
}
