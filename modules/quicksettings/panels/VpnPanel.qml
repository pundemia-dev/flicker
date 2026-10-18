import QtQuick
import "../../../components"
import "../../../config"
import "PanelSync.js" as PanelSync

// Expanded VPN card (QsExpander panel; services/Vpn): header disc = on /
// off, status = the node or the transition, refresh = update the
// subscription. Below, the nodes of the sing-box selector in subscription
// order (tap = switch; pkexec asks), then ping / speed test pills and
// "Subscription…" (URL field + Load; open by itself while there are no
// nodes). Keyboard: the island takes it while this panel is open (the URL
// field); Esc folds the form, then closes.
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null
    signal closeRequested

    readonly property var vpn: root.services?.vpn ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property real fieldH: root.pc.fieldHeight ?? 34
    readonly property color dimColor: root.theme?.cardDim ?? "#99EBEBF5"
    readonly property var profiles: root.vpn?.profiles ?? []
    readonly property string busy: root.vpn?.busy ?? ""
    property bool subOpen: false
    readonly property bool wantsKeyboard: true

    Component.onCompleted: {
        root.syncRows();
        root.forceActiveFocus();
        root.vpn?.refresh();
    }
    onProfilesChanged: root.syncRows()
    // Nothing to pick yet: the subscription form is the point of the panel.
    function syncRows(): void {
        PanelSync.sync(rows, root.profiles, "tag");
        if (root.profiles.length === 0 && (root.vpn?.polled ?? false))
            root.subOpen = true;
    }
    ListModel {
        id: rows
    }
    // A subscription that went through folds its form.
    onBusyChanged: if (root.busy === "" && root.subOpen && root.profiles.length > 0 && !(root.vpn?.error ?? ""))
        root.subOpen = false

    Keys.onPressed: e => {
        if (e.key !== Qt.Key_Escape)
            return;
        if (root.subOpen && root.profiles.length > 0) {
            root.subOpen = false;
            root.forceActiveFocus();
        } else
            root.expander?.close();
        e.accepted = true;
    }

    PanelHeader {
        id: header
        width: parent.width
        pc: root.pc
        theme: root.theme
        frost: root.frost
        pad: root.pad
        on: root.vpn?.on ?? false
        // tabler shield-lock / shield
        glyph: on ? "" : ""
        title: "VPN"
        shape: "cookie9"
        busy: (root.vpn?.status ?? "") === "connecting" || (root.vpn?.status ?? "") === "disconnecting"
        spinning: (root.vpn?.status ?? "") === "active"
        status: {
            const v = root.vpn;
            switch (v?.status ?? "inactive") {
            case "unavailable":
                return I18n.tr("sing-box is not installed");
            case "connecting":
                return v.busy === "select" ? I18n.tr("Switching to %1…").arg(v.selecting) : I18n.tr("Connecting…");
            case "disconnecting":
                return I18n.tr("Disconnecting…");
            case "failed":
                return I18n.tr("Failed");
            case "active":
                return v.profile ? `${I18n.tr("Connected")} · ${v.profile}` : I18n.tr("Connected");
            }
            return I18n.tr("Off");
        }
        onToggled: root.vpn?.toggle()
        trailing: [
            PanelButton {
                visible: root.vpn?.subscription ?? false
                pc: root.pc
                theme: root.theme
                frost: root.frost
                // tabler refresh
                glyph: ""
                spin: root.busy === "update" || root.busy === "subscribe"
                onClicked: root.vpn?.updateSubscription()
            }
        ]
    }

    ListView {
        id: list
        y: header.height + 4
        width: parent.width
        height: parent.height - y - 8
        clip: true
        model: rows
        boundsBehavior: Flickable.StopAtBounds

        header: Text {
            visible: rows.count === 0
            width: list.width
            height: visible ? root.rowH * 1.2 : 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.vpn?.status === "unavailable" ? I18n.tr("Install sing-box to use VPN") : I18n.tr("No servers yet")
            color: root.dimColor
            font.pixelSize: root.pc.textSize ?? 14
        }

        delegate: Item {
            id: row
            required property var model
            readonly property bool current: model.tag === (root.vpn?.profile ?? "")
            readonly property bool switching: root.busy === "select" && root.vpn?.selecting === model.tag
            width: list.width
            height: root.rowH

            Rectangle {
                x: 6
                width: parent.width - 12
                height: parent.height
                radius: height / 2
                color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
                opacity: rowMa.pressed ? 0.8 : rowMa.containsMouse ? 0.45 : 0
                Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
            }
            MouseArea {
                id: rowMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.busy === "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.vpn?.select(row.model.tag)
            }
            Icon {
                id: rowGlyph
                x: root.pad
                width: root.pc.glyphSize ?? 20
                height: parent.height
                // tabler server
                text: ""
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: (root.pc.glyphSize ?? 20) - 2
                iconColor: "white"
            }
            Column {
                x: rowGlyph.x + rowGlyph.width + 12
                width: check.x - x - 8
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    width: parent.width
                    text: row.model.tag
                    color: "white"
                    font.pixelSize: root.pc.textSize ?? 14
                    font.weight: row.current ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: row.switching ? I18n.tr("Switching…") : row.model.type
                    color: root.dimColor
                    font.pixelSize: (root.pc.textSize ?? 14) - 3
                    elide: Text.ElideRight
                }
            }
            Icon {
                id: check
                anchors.right: parent.right
                anchors.rightMargin: root.pad
                height: parent.height
                opacity: row.current ? 1 : 0
                Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
                // tabler check
                text: ""
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: (root.pc.glyphSize ?? 20) - 2
                iconColor: root.theme?.qsBlue ?? "#017EFC"
            }
        }

        footer: Column {
            width: list.width
            topPadding: 8
            spacing: 6

            // Ping / speed test (through whatever route is up — the VPN's
            // when it is on).
            Row {
                x: root.pad
                spacing: 8
                height: root.fieldH
                PanelPill {
                    height: parent.height
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    dim: root.vpn?.pinging ?? false
                    text: {
                        const v = root.vpn;
                        if (v?.pinging)
                            return I18n.tr("Pinging…");
                        if ((v?.pingMs ?? -1) === -2)
                            return I18n.tr("Ping · timeout");
                        return (v?.pingMs ?? -1) >= 0 ? I18n.tr("Ping · %1 ms").arg(v.pingMs) : I18n.tr("Ping");
                    }
                    onClicked: root.vpn?.testPing()
                }
                PanelPill {
                    height: parent.height
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    dim: root.vpn?.speedtesting ?? false
                    text: {
                        const v = root.vpn;
                        if (v?.speedtesting)
                            return I18n.tr("Testing…");
                        if (v?.speedError === "missing")
                            return I18n.tr("No speedtest-cli");
                        if (v?.speedError === "failed")
                            return I18n.tr("Speed test failed");
                        return v?.speed ? `↓${v.speed.down} ↑${v.speed.up} ${I18n.tr("Mbit/s")}` : I18n.tr("Speed test");
                    }
                    onClicked: root.vpn?.testSpeed()
                }
            }

            // Autostart at boot: the whole row is the switch (polkit asks).
            Item {
                id: boot
                width: parent.width
                height: root.rowH
                readonly property bool checked: root.vpn?.enabled ?? false
                Rectangle {
                    x: 6
                    width: parent.width - 12
                    height: parent.height
                    radius: height / 2
                    color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
                    opacity: bootMa.pressed ? 0.8 : bootMa.containsMouse ? 0.45 : 0
                    Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
                }
                Icon {
                    id: bootGlyph
                    x: root.pad
                    width: root.pc.glyphSize ?? 20
                    height: parent.height
                    // tabler power
                    text: ""
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    iconSize: (root.pc.glyphSize ?? 20) - 2
                    iconColor: "white"
                }
                Text {
                    x: bootGlyph.x + bootGlyph.width + 12
                    width: bootSwitch.x - x - 8
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    text: root.busy === "autostart" ? I18n.tr("Applying…") : I18n.tr("Start at boot")
                    color: "white"
                    font.pixelSize: root.pc.textSize ?? 14
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: bootSwitch
                    property real p: boot.checked ? 1 : 0
                    Behavior on p { Spring { stiffness: 5; damp: 0.5; eps: 0.005 } }
                    anchors.right: parent.right
                    anchors.rightMargin: root.pad
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 24
                    radius: height / 2
                    color: switchColor.value
                    opacity: root.busy === "autostart" ? 0.6 : 1
                    SpringColor {
                        id: switchColor
                        target: boot.checked ? (root.theme?.qsBlue ?? "#017EFC")
                            : (root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C"))
                        stiffness: 5
                        damping: 0.6
                    }
                    Rectangle {
                        width: parent.height - 4
                        height: width
                        radius: width / 2
                        y: 2
                        x: 2 + bootSwitch.p * (bootSwitch.width - width - 4)
                        color: "white"
                    }
                }
                MouseArea {
                    id: bootMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.vpn?.setAutostart(!boot.checked)
                }
            }

            // Restart (while on) and the unit's journal in a terminal.
            Row {
                x: root.pad
                spacing: 8
                height: root.fieldH
                PanelPill {
                    visible: root.vpn?.on ?? false
                    height: parent.height
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    dim: root.busy !== ""
                    text: root.busy === "restart" ? I18n.tr("Restarting…") : I18n.tr("Restart service")
                    onClicked: root.vpn?.restart()
                }
                PanelPill {
                    height: parent.height
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    text: I18n.tr("Logs")
                    onClicked: {
                        root.vpn?.openLogs();
                        root.closeRequested();
                    }
                }
            }

            Item {
                id: sub
                width: parent.width
                property real p: root.subOpen ? 1 : 0
                Behavior on p { Spring { stiffness: 5; damp: 0.5; eps: 0.005 } }
                height: Math.round(root.rowH + sub.p * (subForm.implicitHeight + 10))
                onHeightChanged: if (root.subOpen) list.positionViewAtEnd()

                PanelActionRow {
                    panel: root
                    // tabler link
                    glyph: ""
                    label: root.vpn?.subscription ? I18n.tr("Change subscription…") : I18n.tr("Add subscription…")
                    onClicked: {
                        root.subOpen = !root.subOpen;
                        if (!root.subOpen)
                            root.forceActiveFocus();
                    }
                }
                FadeBlur {
                    shown: root.subOpen
                    x: root.pad
                    y: root.rowH + 2
                    width: parent.width - 2 * root.pad
                    height: subForm.implicitHeight
                    onEnabledChanged: if (enabled && root.subOpen) url.focusField()

                    Column {
                        id: subForm
                        width: parent.width
                        spacing: 8
                        Item {
                            width: parent.width
                            height: root.fieldH
                            WifiField {
                                id: url
                                width: parent.width - load.width - 8
                                height: parent.height
                                pc: root.pc
                                theme: root.theme
                                frost: root.frost
                                placeholder: I18n.tr("Subscription URL")
                                onAccepted: load.submit()
                                onEscaped: {
                                    root.subOpen = false;
                                    root.forceActiveFocus();
                                }
                            }
                            PanelPill {
                                id: load
                                function submit(): void {
                                    if (url.text.trim() !== "")
                                        root.vpn?.subscribe(url.text);
                                }
                                anchors.right: parent.right
                                height: parent.height
                                pc: root.pc
                                theme: root.theme
                                frost: root.frost
                                filled: true
                                dim: url.text.trim() === "" || root.busy !== ""
                                text: root.busy === "subscribe" ? I18n.tr("Loading…") : I18n.tr("Import")
                                onClicked: load.submit()
                            }
                        }
                    }
                }
            }

            // Last failure (a dismissed password prompt is not one).
            Text {
                readonly property string err: root.vpn?.error ?? ""
                visible: err !== "" && err !== "cancelled"
                x: root.pad
                width: parent.width - 2 * root.pad
                text: err
                color: root.theme?.accentRed ?? "#E4483E"
                font.pixelSize: (root.pc.textSize ?? 14) - 3
                wrapMode: Text.WordWrap
            }
        }
    }
}
