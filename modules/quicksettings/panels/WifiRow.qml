import QtQuick
import "../../../components"
import "../../../config"

// One network in the Wi‑Fi panel: signal glyph, SSID (+ state line while
// joining / disconnecting / after a failure / behind a captive portal),
// lock for secured networks, check on the current one (pops in), pressed
// to the right edge; on a saved one hover slides them left and "…" fades in
// where they were.
// The row unfolds (panel.openSsid / openMode) into:
//   password  password field (+ user name for WPA‑Enterprise) + Join;
//             Enter joins, Esc folds
//   actions   chips: Details / Share / Disconnect / Forget (Forget asks
//   details   once more); details = the current link (IP, router, DNS,
//   share     band, speed...), share = QR code + the saved password
Item {
    id: root
    required property Item panel
    required property int index
    required property string ssid
    required property int strength
    required property bool secure
    required property bool enterprise
    required property bool active
    required property bool known

    readonly property var pc: root.panel.pc
    readonly property var theme: root.panel.theme
    readonly property var frost: root.panel.frost
    readonly property var net: root.panel.net
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property real fieldH: root.pc.fieldHeight ?? 34
    readonly property color dimColor: root.theme?.cardDim ?? "#99EBEBF5"
    readonly property bool joining: root.net?.connecting === root.ssid
    readonly property bool failed: root.net?.failed === root.ssid
    readonly property bool eap: root.enterprise || root.net?.saved?.[root.ssid]?.keyMgmt === "wpa-eap"
    readonly property bool current: ListView.isCurrentItem && root.panel.keyNav

    // Unfolded part: the live mode, and the last one shown (kept while it
    // folds away).
    readonly property string mode: root.panel.openSsid === root.ssid ? root.panel.openMode : ""
    property string shownMode: ""
    property bool confirmForget: false
    onModeChanged: {
        root.confirmForget = false;
        if (!root.mode)
            return;
        root.shownMode = root.mode;
        if (root.mode === "password") {
            user.clear();
            pass.clear();
            if (form.enabled)
                root.focusForm();
            // Reopened by a failed join: shake once it has unfolded.
            if (root.failed)
                shakeDelay.restart();
        } else if (root.mode === "details")
            root.net?.loadDetails();
        else if (root.mode === "share")
            root.net?.loadShare(root.ssid);
    }
    // Debug IPC (WifiPanel.debug "fill"): type into the open form and Join.
    function fill(name: string, password: string): void {
        user.text = name;
        pass.text = password;
        join.submit();
    }
    function focusForm(): void {
        if (root.eap && user.text.length === 0)
            user.focusField();
        else
            pass.focusField();
    }

    property real p: root.mode ? 1 : 0
    Behavior on p { Spring { stiffness: 5; damp: 0.5; eps: 0.005 } }
    property real extraH: extra.implicitHeight
    Behavior on extraH { Spring { stiffness: 5; damp: 0.6; eps: 0.5 } }
    height: Math.round(root.rowH + root.p * (root.extraH + 10))
    // The unfolded part is laid out at full size while the height springs:
    // without the clip it draws over the rows below.
    clip: root.p > 0.001 && root.p < 0.999 || root.extraH !== extra.implicitHeight
    onHeightChanged: if (root.mode) ListView.view?.positionViewAtIndex(root.index, ListView.Contain)

    readonly property string stateText: {
        if (root.joining)
            return I18n.tr("Connecting…");
        if (root.active && root.net?.disconnecting)
            return I18n.tr("Disconnecting…");
        if (root.failed) {
            const r = root.net?.failReason ?? "";
            return r === "password" ? I18n.tr("Incorrect password")
                : r === "notfound" ? I18n.tr("Network not found")
                : r === "timeout" ? I18n.tr("Timed out")
                : r === "ip" ? I18n.tr("Couldn't get an IP address")
                : (root.net?.failText || I18n.tr("Couldn't connect"));
        }
        if (root.active && root.net?.portal)
            return I18n.tr("Sign-in required");
        return "";
    }

    // Wrong password (iOS): the field row is kicked sideways and springs back.
    Timer {
        id: shakeDelay
        interval: 260
        onTriggered: shakeAnim.restart()
    }
    SpringAnimation {
        id: shakeAnim
        target: shake
        property: "x"
        from: 14
        to: 0
        spring: 6
        damping: 0.12
        epsilon: 0.2
    }

    // Row hover. On the row itself: hover reaches only the topmost item
    // that takes it (the MouseArea / the "…" button) and ITS ancestors — a
    // handler on a sibling item under them never saw the pointer. Counts
    // over the unfolded part too; `overRow` = the row line only.
    HoverHandler {
        id: rowHover
    }
    readonly property bool overRow: rowHover.hovered && rowHover.point.position.y < root.rowH

    // Hover / press / keyboard plate.
    Rectangle {
        x: 6
        width: parent.width - 12
        height: root.rowH
        radius: height / 2
        color: root.frost?.layerColor(root.theme?.qsDisc ?? "#3A3A3C") ?? (root.theme?.qsDisc ?? "#3A3A3C")
        opacity: ma.pressed ? 0.8 : root.overRow || root.current ? 0.45 : 0
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }
    }
    MouseArea {
        id: ma
        width: parent.width
        height: root.rowH
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) root.panel.keyNav = false
        onClicked: e => {
            if (e.button === Qt.RightButton)
                root.panel.menu(root.netInfo());
            else
                root.panel.tap(root.netInfo());
        }
        onPressAndHold: root.panel.menu(root.netInfo())
    }
    function netInfo(): var {
        return { ssid: root.ssid, secure: root.secure, enterprise: root.eap, active: root.active, known: root.known };
    }

    Icon {
        id: glyph
        x: root.panel.pad
        width: root.pc.glyphSize ?? 20
        height: root.rowH
        // tabler wifi / wifi-2 / wifi-1 / wifi-0
        text: root.strength >= 70 ? "" : root.strength >= 45 ? "" : root.strength >= 20 ? "" : ""
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: root.pc.glyphSize ?? 20
        iconColor: "white"
    }

    Column {
        x: glyph.x + glyph.width + 12
        width: tail.x - x - 8
        y: Math.round((root.rowH - height) / 2)
        Text {
            width: parent.width
            text: root.ssid
            color: "white"
            font.pixelSize: root.pc.textSize ?? 14
            font.weight: root.active ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
        }
        // State line: unfolds / folds (keeps its last text while it goes).
        Item {
            id: stateLine
            property real p: root.stateText !== "" ? 1 : 0
            Behavior on p { Spring { stiffness: 6; damp: 0.6; eps: 0.005 } }
            property string shown: ""
            readonly property string live: root.stateText
            onLiveChanged: if (live) shown = live
            Component.onCompleted: shown = live
            width: parent.width
            height: Math.round(stateText.implicitHeight * Math.max(0, Math.min(1, p)))
            visible: p > 0.01
            Text {
                id: stateText
                width: parent.width
                y: (1 - stateLine.p) * -4
                opacity: Math.max(0, Math.min(1, stateLine.p))
                text: stateLine.shown
                color: root.failed && !root.joining ? (root.theme?.accentRed ?? "#E4483E")
                    : root.active && root.net?.portal ? (root.theme?.accentOrange ?? "#E58B4D") : root.dimColor
                font.pixelSize: (root.pc.textSize ?? 14) - 3
                elide: Text.ElideRight
            }
        }
    }

    // Lock / check pressed to the right edge; on a saved network hover
    // (or the keyboard selection / an open row) slides them left by the "…"
    // slot and the button fades + grows in there.
    Item {
        id: tail
        readonly property real dotsSize: 28
        readonly property bool dotsWanted: (root.known || root.active)
            && (rowHover.hovered || root.current || root.mode !== "")
        property real reveal: tail.dotsWanted ? 1 : 0
        Behavior on reveal { Spring { stiffness: 5; damp: 0.55; eps: 0.005 } }
        readonly property real revealC: Math.max(0, Math.min(1, tail.reveal))
        anchors.right: parent.right
        anchors.rightMargin: root.panel.pad - 6
        height: root.rowH
        width: icons.width + (tail.dotsSize + 4) * tail.reveal

        Row {
            id: icons
            height: parent.height
            spacing: 4
            Icon {
                visible: root.secure
                height: parent.height
                // tabler lock
                text: "\ueae2"
                font.family: root.theme?.iconFamily ?? "tabler-icons"
                iconSize: (root.pc.glyphSize ?? 20) - 4
                iconColor: root.dimColor
            }
            // Check: pops in on a spring when the network becomes current.
            Item {
                id: check
                property real p: root.active ? 1 : 0
                Behavior on p { Spring { stiffness: 5; damp: 0.4; eps: 0.005 } }
                visible: p > 0.01
                width: checkIcon.implicitWidth * Math.max(0, Math.min(1, p))
                height: parent.height
                Icon {
                    id: checkIcon
                    anchors.centerIn: parent
                    height: parent.height
                    scale: Math.max(0, check.p)
                    opacity: Math.max(0, Math.min(1, check.p))
                    // tabler check
                    text: "\uea5e"
                    font.family: root.theme?.iconFamily ?? "tabler-icons"
                    iconSize: (root.pc.glyphSize ?? 20) - 2
                    iconColor: root.theme?.qsBlue ?? "#017EFC"
                }
            }
        }
        // Saved network: the actions without a right click / long press.
        PanelButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: tail.revealC > 0.01
            enabled: tail.dotsWanted
            opacity: tail.revealC
            scale: 0.5 + 0.5 * tail.revealC
            size: tail.dotsSize
            pc: root.pc
            theme: root.theme
            frost: root.frost
            // tabler dots
            glyph: "\uea95"
            onClicked: root.panel.menu(root.netInfo())
        }
    }

    // Unfolded part ---------------------------------------------------------
    // A section fades + rises in when it becomes the shown one (the row's
    // height already springs to it; a crossfade would stack both). The rise
    // goes through a Translate (`shift`): the Column owns the y.
    component Appear: ParallelAnimation {
        id: ap
        property Item target: null
        property Translate shift: null
        Spring { target: ap.target; property: "opacity"; from: 0; to: 1; stiffness: 6; damp: 0.6; eps: 0.01 }
        Spring { target: ap.shift; property: "y"; from: 6; to: 0; stiffness: 5; damp: 0.5; eps: 0.1 }
    }
    FadeBlur {
        id: form
        shown: root.mode !== ""
        x: root.panel.pad
        y: root.rowH + 2
        width: parent.width - 2 * root.panel.pad
        height: extra.implicitHeight
        onEnabledChanged: if (enabled && root.mode === "password") root.focusForm()

        Column {
            id: extra
            width: parent.width
            spacing: 8

            // Password (+ user name).
            WifiField {
                id: user
                visible: root.shownMode === "password" && root.eap
                width: parent.width
                height: root.fieldH
                transform: Translate { x: shake.x }
                pc: root.pc
                theme: root.theme
                frost: root.frost
                placeholder: I18n.tr("User name")
                onAccepted: pass.focusField()
                onEscaped: root.panel.fold()
            }
            Item {
                id: passRow
                visible: root.shownMode === "password"
                onVisibleChanged: if (visible) passIn.restart()
                Appear { id: passIn; target: passRow; shift: passShift }
                width: parent.width
                height: root.fieldH
                transform: [
                    Translate { id: shake },
                    Translate { id: passShift }
                ]
                WifiField {
                    id: pass
                    width: parent.width - join.width - 8
                    height: parent.height
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    password: true
                    placeholder: I18n.tr("Password")
                    onAccepted: join.submit()
                    onEscaped: root.panel.fold()
                }
                PanelPill {
                    id: join
                    readonly property bool ready: pass.text.length > 0 && (!root.eap || user.text.length > 0)
                    function submit(): void {
                        if (!join.ready)
                            return;
                        root.net?.join(root.ssid, pass.text, { identity: user.text });
                        root.panel.fold();
                    }
                    anchors.right: parent.right
                    height: parent.height
                    pc: root.pc
                    theme: root.theme
                    frost: root.frost
                    filled: true
                    dim: !join.ready
                    text: I18n.tr("Join")
                    onClicked: join.submit()
                }
            }

            // Action chips.
            // They pop in one after another each time the actions show.
            Flow {
                id: chips
                visible: root.shownMode !== "password"
                readonly property bool live: chips.visible && root.mode !== ""
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        root.active ? "details" : "",
                        root.known && !root.eap ? "share" : "",
                        root.active ? "disconnect" : "",
                        root.known ? "forget" : ""
                    ].filter(a => a)
                    PanelPill {
                        id: chip
                        required property string modelData
                        required property int index
                        property real inP: chips.live ? 1 : 0
                        readonly property bool live: chips.live
                        onLiveChanged: if (live) chipIn.restart()
                        Component.onCompleted: if (live) chipIn.restart()
                        SequentialAnimation {
                            id: chipIn
                            PropertyAction { target: chip; property: "inP"; value: 0 }
                            PauseAnimation { duration: 40 + chip.index * 45 }
                            Spring { target: chip; property: "inP"; to: 1; stiffness: 6; damp: 0.4; eps: 0.005 }
                        }
                        opacity: Math.max(0, Math.min(1, chip.inP))
                        transform: Scale {
                            origin.x: chip.width / 2
                            origin.y: chip.height / 2
                            xScale: 0.7 + 0.3 * chip.inP
                            yScale: 0.7 + 0.3 * chip.inP
                        }
                        height: Math.round(root.fieldH * 0.85)
                        pc: root.pc
                        theme: root.theme
                        frost: root.frost
                        checked: root.mode === modelData || (modelData === "forget" && root.confirmForget)
                        danger: modelData === "forget"
                        text: ({
                            details: I18n.tr("Details"),
                            share: I18n.tr("Share"),
                            disconnect: I18n.tr("Disconnect"),
                            forget: root.confirmForget ? I18n.tr("Forget this network?") : I18n.tr("Forget")
                        })[modelData]
                        onClicked: root.panel.action(root.ssid, modelData)
                    }
                }
            }

            // Details of the current link.
            Grid {
                id: detailsGrid
                visible: root.shownMode === "details"
                onVisibleChanged: if (visible) detailsIn.restart()
                Appear { id: detailsIn; target: detailsGrid; shift: detailsShift }
                transform: Translate { id: detailsShift }
                width: parent.width
                columns: 2
                columnSpacing: 12
                rowSpacing: 3
                Repeater {
                    model: {
                        const d = root.net?.details;
                        if (!d)
                            return [I18n.tr("Loading…"), ""];
                        return [
                            [I18n.tr("IP address"), d.ip],
                            [I18n.tr("Router"), d.gateway],
                            [I18n.tr("DNS"), d.dns],
                            [I18n.tr("Band"), d.band && d.channel ? `${d.band} · ${I18n.tr("channel %1").arg(d.channel)}` : d.band],
                            [I18n.tr("Speed"), d.rate],
                            [I18n.tr("Security"), d.security],
                            ["BSSID", d.bssid],
                            ["MAC", d.mac]
                        ].filter(r => r[1]).reduce((a, r) => a.concat(r), []);
                    }
                    // Values fade in as they arrive (Loading… → the link).
                    Text {
                        required property string modelData
                        required property int index
                        Spring on opacity { from: 0; to: 1; stiffness: 6; damp: 0.6; eps: 0.01 }
                        width: index % 2 ? extra.width - 12 - 92 : 92
                        text: modelData
                        color: index % 2 ? "white" : root.dimColor
                        font.pixelSize: (root.pc.textSize ?? 14) - 2
                        elide: Text.ElideRight
                    }
                }
            }

            // QR code + password.
            Row {
                id: shareRow
                visible: root.shownMode === "share"
                onVisibleChanged: if (visible) shareIn.restart()
                Appear { id: shareIn; target: shareRow; shift: shareShift }
                transform: Translate { id: shareShift }
                spacing: 14
                readonly property var s: root.net?.share?.ssid === root.ssid ? root.net.share : null
                Rectangle {
                    width: 112
                    height: 112
                    radius: 10
                    color: "white"
                    // The code fades + grows in once generated.
                    Image {
                        id: qr
                        anchors.fill: parent
                        anchors.margins: 4
                        source: parent.parent.s?.qr ?? ""
                        smooth: false
                        fillMode: Image.PreserveAspectFit
                        property real p: qr.status === Image.Ready ? 1 : 0
                        Behavior on p { Spring { stiffness: 5; damp: 0.5; eps: 0.005 } }
                        opacity: Math.max(0, Math.min(1, qr.p))
                        scale: 0.85 + 0.15 * qr.p
                    }
                }
                Column {
                    width: extra.width - 112 - 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        width: parent.width
                        text: I18n.tr("Scan with a phone camera to join")
                        color: root.dimColor
                        font.pixelSize: (root.pc.textSize ?? 14) - 3
                        wrapMode: Text.WordWrap
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Password")
                        color: root.dimColor
                        font.pixelSize: (root.pc.textSize ?? 14) - 3
                        topPadding: 4
                    }
                    TextEdit {
                        width: parent.width
                        readOnly: true
                        selectByMouse: true
                        text: !parent.parent.s ? "…" : (parent.parent.s.password || I18n.tr("No password"))
                        color: "white"
                        selectionColor: root.theme?.qsBlue ?? "#017EFC"
                        font.pixelSize: root.pc.textSize ?? 14
                        wrapMode: TextEdit.WrapAnywhere
                    }
                }
            }
        }
    }
}
