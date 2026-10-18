import QtQuick
import QtQuick.Window
import "../../../components"
import "../../../config"
import "PanelSync.js" as PanelSync

// Expanded Wi‑Fi card (QsExpander panel): header = the card's glyph disc
// (tap toggles Wi‑Fi) + title + current network + rescan button; below,
// the networks (services/Network list, refreshed and rescanned while this
// panel exists) in two sections, saved and other; a captive-portal sign-in
// row on top when NM reports one; "Other network…" (hidden SSID) and
// "Network settings…" (nmtui) at the bottom.
// Tap: current network → its details; saved / open → join; new secured →
// password field in its row. Right click / long press / the row's "…" =
// the actions (details, share as QR, disconnect, forget).
// Keyboard (the island takes it while this panel is open, `wantsKeyboard`):
// ↑/↓ move, Enter = tap, → = actions, ← folds, Esc folds / closes.
// Services come from the factory's Component, `expander` from DropExpand.
Item {
    id: root
    property var services: null
    property var cfg: null
    property var theme: null
    property var frost: null
    property var expander: null
    signal closeRequested

    readonly property var net: root.services?.network ?? null
    readonly property var pc: root.cfg?.listPanel ?? ({})
    readonly property real pad: root.pc.padding ?? 18
    readonly property real rowH: root.pc.rowHeight ?? 42
    readonly property real fieldH: root.pc.fieldHeight ?? 34
    readonly property bool on: root.net?.wifiEnabled ?? false
    readonly property color dimColor: root.theme?.cardDim ?? "#99EBEBF5"
    // Unfolded row (WifiRow modes) and the hidden-network form.
    property string openSsid: ""
    property string openMode: ""
    property bool otherOpen: false
    // The footer's hidden-network row (debug "other" types into it).
    property Item otherForm: null
    // Arrows moved the selection (the current row shows its plate) — until
    // the pointer hovers a row again.
    property bool keyNav: false
    readonly property bool wantsKeyboard: true

    onNetChanged: root.net?.setScanning(true)
    Component.onCompleted: root.forceActiveFocus()
    Component.onDestruction: root.net?.setScanning(false)

    // Stable order: current, saved (by name), others by signal bars then
    // name — a raw signal sort reshuffled rows on every scan.
    function bars(s: int): int {
        return s >= 70 ? 3 : s >= 45 ? 2 : s >= 20 ? 1 : 0;
    }
    readonly property var sorted: {
        if (!root.on)
            return [];
        return (root.net?.networks ?? []).slice().sort((a, b) => (b.active - a.active) || (b.known - a.known)
            || (a.known ? 0 : root.bars(b.signal) - root.bars(a.signal)) || a.ssid.localeCompare(b.ssid))
            .map(n => Object.assign({ group: n.active || n.known ? "saved" : "other" }, n));
    }
    // ListModel synced in place (PanelSync).
    onSortedChanged: {
        PanelSync.sync(rows, root.sorted, "ssid");
        if (root.openSsid && !root.sorted.some(n => n.ssid === root.openSsid))
            root.fold();
        if (list.currentIndex >= rows.count)
            list.currentIndex = Math.max(0, rows.count - 1);
    }
    ListModel {
        id: rows
    }

    // A failed join: ask for the password again when that is the reason (or
    // the network was never joined); a hidden one keeps its form open.
    Connections {
        target: root.net
        function onFailedChanged(): void {
            const f = root.net.failed;
            if (!f || root.otherOpen)
                return;
            const n = root.net.networks.find(x => x.ssid === f);
            if (n?.secure && (!n.known || root.net.failReason === "password"))
                root.setMode(f, "password");
        }
        // The hidden-network form folds once its join went through.
        function onConnectingChanged(): void {
            if (!root.net.connecting && root.otherOpen && !root.net.failed)
                root.fold();
        }
    }

    function setMode(ssid: string, mode: string): void {
        root.otherOpen = false;
        root.openSsid = mode ? ssid : "";
        root.openMode = mode;
        if (!mode)
            root.forceActiveFocus();
    }
    function toggle(ssid: string, mode: string): void {
        root.setMode(ssid, root.openSsid === ssid && root.openMode === mode ? "" : mode);
    }
    function fold(): void {
        root.setMode("", "");
    }

    function tap(n: var): void {
        if (root.net?.connecting)
            return;
        if (n.active) {
            root.toggle(n.ssid, "details");
            return;
        }
        if (n.secure && !n.known) {
            root.toggle(n.ssid, "password");
            return;
        }
        root.fold();
        root.net?.join(n.ssid, "", null);
    }
    // Actions of a saved / the current network (right click, long press,
    // "…", →); an unsaved one has none.
    function menu(n: var): void {
        if (root.openSsid === n.ssid)
            root.fold();
        else if (n.known || n.active)
            root.setMode(n.ssid, "actions");
    }
    function action(ssid: string, a: string): void {
        if (a === "details" || a === "share")
            root.setMode(ssid, root.openMode === a ? "actions" : a);
        else if (a === "disconnect") {
            root.fold();
            root.net?.disconnect();
        } else if (a === "forget") {
            // Twice on the row: the chip asks first.
            const row = list.itemAtIndex(root.indexOf(ssid));
            if (!row)
                return;
            if (!row.confirmForget) {
                row.confirmForget = true;
                return;
            }
            root.fold();
            root.net?.forget(ssid);
        }
    }
    function indexOf(ssid: string): int {
        for (let i = 0; i < rows.count; i++)
            if (rows.get(i).ssid === ssid)
                return i;
        return -1;
    }

    function move(d: int): void {
        if (rows.count === 0)
            return;
        if (root.keyNav)
            list.currentIndex = Math.max(0, Math.min(rows.count - 1, list.currentIndex + d));
        root.keyNav = true;
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }
    function currentNet(): var {
        return list.currentItem?.netInfo() ?? null;
    }
    // Debug IPC (island quicksettingsPanel <cmd> <arg>; "|" splits args):
    // state, tap/menu <ssid>, action <ssid|details|share|disconnect|forget>,
    // fill <user|password> (the open row's form), other <ssid|password>,
    // forget <ssid> (no row, no confirmation),
    // fold, rescan, portal (fakes NM's state until the next poll), settings.
    // Returns the state JSON after the command.
    function debug(cmd: string, arg: string): string {
        const a = (arg ?? "").split("|");
        // From the model: a row scrolled out of the view has no delegate.
        const info = ssid => root.sorted.find(n => n.ssid === ssid) ?? null;
        if (cmd === "tap" && info(a[0]))
            root.tap(info(a[0]));
        else if (cmd === "menu" && info(a[0]))
            root.menu(info(a[0]));
        else if (cmd === "action")
            root.action(a[0], a[1]);
        else if (cmd === "fill")
            list.itemAtIndex(root.indexOf(root.openSsid))?.fill(a[0] ?? "", a[1] ?? "");
        else if (cmd === "other") {
            root.fold();
            root.otherOpen = true;
            root.otherForm?.fill(a[0], a[1] ?? "");
        } else if (cmd === "forget")
            root.net?.forget(a[0]);
        else if (cmd === "fold")
            root.fold();
        else if (cmd === "rescan")
            root.net?.rescan();
        else if (cmd === "portal" && root.net)
            root.net.connectivity = "portal";
        else if (cmd === "settings")
            root.net?.openSettings();
        const net = root.net;
        const row = list.itemAtIndex(root.indexOf(root.openSsid));
        const sh = net?.share;
        return JSON.stringify({
            openSsid: root.openSsid, openMode: root.openMode, otherOpen: root.otherOpen,
            keyNav: root.keyNav, current: list.currentItem?.ssid ?? "",
            focus: String(root.Window.activeFocusItem ?? ""), panelFocus: root.activeFocus,
            row: row ? { mode: row.mode, height: row.height, state: row.stateText, confirmForget: row.confirmForget } : null,
            status: header.status,
            rows: root.sorted.map(n => `${n.group}:${n.ssid}${n.active ? "*" : ""}${n.known ? "+" : ""}${n.secure ? "#" : ""}`),
            net: net ? {
                wifiSsid: net.wifiSsid, connectivity: net.connectivity, portal: net.portal,
                connecting: net.connecting, failed: net.failed, failReason: net.failReason, failText: net.failText,
                rescanning: net.rescanning, disconnecting: net.disconnecting, details: net.details,
                share: sh ? { ssid: sh.ssid, passwordLen: sh.password.length, qrLen: sh.qr.length } : null,
                saved: Object.keys(net.saved)
            } : null
        });
    }

    Keys.onPressed: e => {
        const n = root.keyNav ? root.currentNet() : null;
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Up)
            root.move(e.key === Qt.Key_Down ? 1 : -1);
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && n)
            root.tap(n);
        else if ((e.key === Qt.Key_Right || e.key === Qt.Key_Menu) && n)
            root.menu(n);
        else if (e.key === Qt.Key_Left)
            root.fold();
        else if (e.key === Qt.Key_Escape) {
            if (root.openSsid || root.otherOpen)
                root.fold();
            else
                root.expander?.close();
        } else
            return;
        e.accepted = true;
    }

    PanelHeader {
        id: header
        width: parent.width
        pc: root.pc
        theme: root.theme
        frost: root.frost
        pad: root.pad
        on: root.on
        // tabler wifi / wifi-off
        glyph: root.on ? "" : ""
        title: "Wi‑Fi"
        status: {
            const net = root.net;
            if (!root.on)
                return I18n.tr("Off");
            if (net?.connecting)
                return I18n.tr("Connecting to %1…").arg(net.connecting);
            if (!net?.wifiConnected)
                return I18n.tr("Not connected");
            return net.portal ? `${net.wifiSsid} · ${I18n.tr("Sign-in required")}` : net.wifiSsid;
        }
        onToggled: root.net?.toggleWifi()
        trailing: [
            PanelButton {
                visible: root.on
                pc: root.pc
                theme: root.theme
                frost: root.frost
                // tabler refresh
                glyph: ""
                spin: root.net?.rescanning ?? false
                onClicked: root.net?.rescan()
            }
        ]
    }

    // Networks -------------------------------------------------------------
    ListView {
        id: list
        y: header.height + 4
        width: parent.width
        height: parent.height - y - 8
        clip: true
        model: rows
        keyNavigationEnabled: false
        boundsBehavior: Flickable.StopAtBounds

        // Rows come and go with a fade + small grow (the first fill
        // cascades), the rest springs into place; a re-sort slides.
        add: Transition {
            id: addTr
            SequentialAnimation {
                PropertyAction { property: "opacity"; value: 0 }
                PauseAnimation { duration: Math.min(addTr.ViewTransition.index, 10) * 22 }
                ParallelAnimation {
                    Spring { property: "opacity"; from: 0; to: 1; stiffness: 6; damp: 0.6; eps: 0.01 }
                    Spring { property: "scale"; from: 0.92; to: 1; stiffness: 5; damp: 0.45; eps: 0.002 }
                }
            }
        }
        remove: Transition {
            ParallelAnimation {
                Spring { property: "opacity"; to: 0; stiffness: 8; damp: 0.8; eps: 0.02 }
                Spring { property: "scale"; to: 0.92; stiffness: 8; damp: 0.8; eps: 0.005 }
            }
        }
        move: Transition {
            Spring { property: "y"; stiffness: 5; damp: 0.55; eps: 0.3 }
        }
        displaced: Transition {
            ParallelAnimation {
                Spring { property: "y"; stiffness: 5; damp: 0.55; eps: 0.3 }
                // An add interrupted mid-fade must not stay translucent.
                Spring { property: "opacity"; to: 1; stiffness: 6; damp: 0.6; eps: 0.01 }
                Spring { property: "scale"; to: 1; stiffness: 6; damp: 0.6; eps: 0.002 }
            }
        }

        header: Column {
            width: list.width
            PanelActionRow {
                panel: root
                visible: root.net?.portal ?? false
                // tabler world
                glyph: ""
                label: I18n.tr("Sign in to the network…")
                tint: root.theme?.accentOrange ?? "#E58B4D"
                onClicked: {
                    root.net.openPortal();
                    root.closeRequested();
                }
            }
            Text {
                visible: rows.count === 0
                width: parent.width
                height: root.rowH * 1.5
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: !root.on ? I18n.tr("Wi‑Fi is off") : I18n.tr("Searching…")
                color: root.dimColor
                font.pixelSize: root.pc.textSize ?? 14
            }
        }

        section.property: "group"
        section.delegate: Text {
            required property string section
            x: root.pad
            width: list.width - 2 * root.pad
            height: 26
            verticalAlignment: Text.AlignBottom
            bottomPadding: 3
            text: section === "saved" ? I18n.tr("Known networks") : I18n.tr("Other networks")
            color: root.dimColor
            font.pixelSize: (root.pc.textSize ?? 14) - 3
            font.weight: Font.DemiBold
        }

        delegate: WifiRow {
            required property var model
            width: list.width
            panel: root
            ssid: model.ssid
            strength: model.signal
            secure: model.secure
            enterprise: model.enterprise
            active: model.active
            known: model.known
        }

        footer: Column {
            width: list.width
            topPadding: 6

            // Hidden network: SSID + password (empty = open).
            Item {
                id: other
                visible: root.on
                width: parent.width
                property real p: root.otherOpen ? 1 : 0
                Behavior on p { Spring { stiffness: 5; damp: 0.5; eps: 0.005 } }
                height: Math.round(root.rowH + other.p * (otherForm.implicitHeight + 10))
                onHeightChanged: if (root.otherOpen) list.positionViewAtEnd()
                readonly property bool failed: root.net?.failed !== "" && root.net?.failed === otherSsid.text
                Component.onCompleted: root.otherForm = other
                function fill(ssid: string, password: string): void {
                    otherSsid.text = ssid;
                    otherPass.text = password;
                    otherJoin.submit();
                }

                PanelActionRow {
                    panel: root
                    // tabler plus
                    glyph: ""
                    label: I18n.tr("Other network…")
                    onClicked: {
                        const open = !root.otherOpen;
                        root.fold();
                        root.otherOpen = open;
                        if (open) {
                            otherSsid.clear();
                            otherPass.clear();
                        }
                    }
                }
                FadeBlur {
                    shown: root.otherOpen
                    x: root.pad
                    y: root.rowH + 2
                    width: parent.width - 2 * root.pad
                    height: otherForm.implicitHeight
                    onEnabledChanged: if (enabled && root.otherOpen) otherSsid.focusField()

                    Column {
                        id: otherForm
                        width: parent.width
                        spacing: 8
                        WifiField {
                            id: otherSsid
                            width: parent.width
                            height: root.fieldH
                            pc: root.pc
                            theme: root.theme
                            frost: root.frost
                            placeholder: I18n.tr("Network name")
                            onAccepted: otherPass.focusField()
                            onEscaped: root.fold()
                        }
                        Item {
                            width: parent.width
                            height: root.fieldH
                            WifiField {
                                id: otherPass
                                width: parent.width - otherJoin.width - 8
                                height: parent.height
                                pc: root.pc
                                theme: root.theme
                                frost: root.frost
                                password: true
                                placeholder: I18n.tr("Password (none = open)")
                                onAccepted: otherJoin.submit()
                                onEscaped: root.fold()
                            }
                            PanelPill {
                                id: otherJoin
                                function submit(): void {
                                    if (!otherSsid.text || root.net?.connecting)
                                        return;
                                    root.net?.join(otherSsid.text, otherPass.text, { hidden: true });
                                }
                                anchors.right: parent.right
                                height: parent.height
                                pc: root.pc
                                theme: root.theme
                                frost: root.frost
                                filled: true
                                dim: !otherSsid.text
                                text: I18n.tr("Join")
                                onClicked: otherJoin.submit()
                            }
                        }
                        Text {
                            readonly property string ssid: otherSsid.text
                            visible: text !== ""
                            width: parent.width
                            text: root.net?.connecting !== "" && root.net?.connecting === ssid ? I18n.tr("Connecting…")
                                : other.failed ? (root.net.failReason === "password" ? I18n.tr("Incorrect password")
                                    : root.net.failReason === "notfound" ? I18n.tr("Network not found")
                                    : (root.net.failText || I18n.tr("Couldn't connect"))) : ""
                            color: other.failed ? (root.theme?.accentRed ?? "#E4483E") : root.dimColor
                            font.pixelSize: (root.pc.textSize ?? 14) - 3
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            PanelActionRow {
                panel: root
                // tabler settings
                glyph: ""
                label: I18n.tr("Network settings…")
                tint: root.dimColor
                onClicked: {
                    root.net?.openSettings();
                    root.closeRequested();
                }
            }
        }
    }
}
