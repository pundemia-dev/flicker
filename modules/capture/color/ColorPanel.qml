import QtQuick
import "../../../components"
import "ColorMath.js" as ColorMath
import "../../../config"

// Picked-colour panel (port of pShell ColorPanel, plain rounded panel
// instead of the SDF blob): live + picked previews, an editable value field
// (hex / rgb() / hsl()), format chips, HSL sliders and the recent colours.
// Opens next to the pick, a follow radius away from it; a pick farther than
// colorPanelMoveThreshold makes it crawl back onto the radius (spring).
// Every pick / format switch / edit re-copies silently.
Item {
    id: root
    required property var picker

    readonly property var cfg: root.picker.cfg
    readonly property var theme: root.picker.theme
    readonly property var actions: root.picker.actions

    property bool open: false
    property real hue: 0
    property real sat: 0
    property real lig: 0
    property string fmt: "hex"
    property real panelX: 0
    property real panelY: 0

    readonly property color cur: Qt.hsla(root.hue, root.sat, root.lig, 1)
    readonly property int rC: Math.round(root.cur.r * 255)
    readonly property int gC: Math.round(root.cur.g * 255)
    readonly property int bC: Math.round(root.cur.b * 255)
    readonly property string valueText: ColorMath.format(root.rC, root.gC, root.bC, root.fmt)
    readonly property bool hovering: panelHover.hovered
    readonly property bool fieldFocused: valField.activeFocus
    readonly property real panelW: root.cfg.colorPanelWidth
    readonly property real panelH: col.implicitHeight + root.cfg.panelPad * 2
    readonly property real gap: root.cfg.toolSpacing

    function initialFmt(): string {
        const def = root.cfg.colorDefaultFormat;
        return def === "auto" ? (root.actions.lastColorFormat || "hex") : def;
    }

    function setRgb(r: int, g: int, b: int): void {
        const c = Qt.rgba(r / 255, g / 255, b / 255, 1);
        root.hue = Math.max(0, c.hslHue);
        root.sat = c.hslSaturation;
        root.lig = c.hslLightness;
    }

    function copySilently(): void {
        root.actions.copyText(root.valueText, "");
    }

    function show(r: int, g: int, b: int): void {
        root.setRgb(r, g, b);
        const cx = root.picker.cursorX, cy = root.picker.cursorY;
        if (!root.open) {
            root.fmt = root.initialFmt();
            // Toward the screen centre, a follow radius away from the pick.
            const p = root.placeOnRadius(cx, cy, root.width / 2 - cx, root.height / 2 - cy);
            posX.enabled = posY.enabled = false;
            root.panelX = p.x;
            root.panelY = p.y;
            posX.enabled = posY.enabled = true;
            root.open = true;
        } else {
            root.maybeCrawl(cx, cy);
        }
        root.actions.addRecent(root.rC, root.gC, root.bC);
        root.copySilently();
    }

    function selectFmt(f: string): void {
        if (root.fmt === f)
            return;
        root.fmt = f;
        root.actions.lastColorFormat = f;
        root.copySilently();
    }

    function applyText(t: string): void {
        const c = ColorMath.parse(t);
        if (!c)
            return; // invalid: the field snaps back to the bound value
        if (c.h !== undefined) {
            root.hue = c.h;
            root.sat = c.s;
            root.lig = c.l;
        } else {
            root.setRgb(c.r, c.g, c.b);
        }
        root.copySilently();
    }

    // Position whose nearest EDGE lands on the follow radius from (cx, cy),
    // approached along (dx, dy). Thresholds are % of screen height.
    function placeOnRadius(cx: real, cy: real, dx: real, dy: real): point {
        const radius = root.height * root.cfg.colorPanelFollowRadius / 100;
        const len = Math.hypot(dx, dy) || 1;
        dx /= len;
        dy /= len;
        const edge = Math.min(dx !== 0 ? (root.panelW / 2) / Math.abs(dx) : 1e9, dy !== 0 ? (root.panelH / 2) / Math.abs(dy) : 1e9);
        return Qt.point(Math.max(root.gap, Math.min(root.width - root.panelW - root.gap, cx + dx * (radius + edge) - root.panelW / 2)),
            Math.max(root.gap, Math.min(root.height - root.panelH - root.gap, cy + dy * (radius + edge) - root.panelH / 2)));
    }

    function maybeCrawl(cx: real, cy: real): void {
        const nx = Math.max(root.panelX, Math.min(cx, root.panelX + root.panelW));
        const ny = Math.max(root.panelY, Math.min(cy, root.panelY + root.panelH));
        if (Math.hypot(cx - nx, cy - ny) <= root.height * root.cfg.colorPanelMoveThreshold / 100)
            return;
        const p = root.placeOnRadius(cx, cy, root.panelX + root.panelW / 2 - cx, root.panelY + root.panelH / 2 - cy);
        root.panelX = p.x;
        root.panelY = p.y;
    }

    Behavior on panelX { id: posX; Spring {} }
    Behavior on panelY { id: posY; Spring {} }

    visible: opacity > 0.01
    opacity: root.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: root.cfg.fadeInMs } }

    Rectangle {
        x: root.panelX
        y: root.panelY
        width: root.panelW
        height: root.panelH
        radius: root.cfg.panelRadius
        color: root.theme.islandBg

        HoverHandler { id: panelHover }
        MouseArea { anchors.fill: parent } // no picks through the panel

        Column {
            id: col
            anchors.centerIn: parent
            width: root.panelW - root.cfg.panelPad * 2
            spacing: root.gap * 1.5

            Item {
                width: parent.width
                height: previews.height

                Row {
                    id: previews
                    spacing: root.gap * 2
                    Repeater {
                        model: [
                            { label: I18n.tr("cursor"), picked: false },
                            { label: I18n.tr("picked"), picked: true }
                        ]
                        Column {
                            required property var modelData
                            spacing: root.gap / 2
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: root.cfg.toolButtonSize
                                height: width
                                radius: width / 2
                                readonly property var live: root.picker.liveColor
                                color: parent.modelData.picked ? root.cur
                                    : (live ? Qt.rgba(live.r / 255, live.g / 255, live.b / 255, 1) : "transparent")
                                border.width: parent.modelData.picked ? 2 : 1
                                border.color: parent.modelData.picked ? root.theme.islandFg : root.theme.cardTrack
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: parent.modelData.label
                                color: root.theme.subtleFg
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSizeTiny
                            }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: root.gap
                    IconButton {
                        theme: root.theme
                        width: root.cfg.toolButtonSize
                        height: width
                        glyph: ""
                        iconSize: root.cfg.toolIconSize
                        onClicked: root.actions.copyText(root.valueText, I18n.tr("Color copied"))
                    }
                    IconButton {
                        theme: root.theme
                        width: root.cfg.toolButtonSize
                        height: width
                        glyph: ""
                        iconSize: root.cfg.toolIconSize
                        onClicked: root.open = false
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: valField.implicitHeight + root.cfg.panelPad
                radius: root.cfg.toolRadius
                color: root.theme.cardBg
                border.width: valField.activeFocus ? 2 : 0
                border.color: root.theme.cardBlue

                TextInput {
                    id: valField
                    property bool escCancel: false
                    anchors.fill: parent
                    anchors.margins: root.cfg.panelPad / 2
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.theme.islandFg
                    selectionColor: root.theme.cardBlue
                    selectByMouse: true
                    clip: true
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSizeClock
                    font.features: { "tnum": 1 }
                    text: root.valueText
                    onAccepted: focus = false
                    Keys.onEscapePressed: {
                        escCancel = true;
                        focus = false;
                    }
                    onActiveFocusChanged: {
                        if (activeFocus)
                            return;
                        if (!escCancel)
                            root.applyText(text);
                        escCancel = false;
                        text = Qt.binding(() => root.valueText);
                        root.picker.keyTarget.forceActiveFocus();
                    }
                }
            }

            Row {
                spacing: root.gap
                Repeater {
                    model: ["hex", "rgb", "rgba", "hsl"]
                    Rectangle {
                        id: chip
                        required property string modelData
                        width: chipText.implicitWidth + root.cfg.panelPad
                        height: chipText.implicitHeight + root.gap
                        radius: height / 2
                        color: root.fmt === modelData ? root.theme.cardBlue : root.theme.cardBg
                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData.toUpperCase()
                            color: root.theme.islandFg
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSizeIndicator
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectFmt(chip.modelData)
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: root.gap
                ColorSlider {
                    width: parent.width
                    height: root.cfg.toolIconSize
                    theme: root.theme
                    growMs: root.cfg.fadeOutMs
                    value: root.hue
                    colorAt: t => Qt.hsla(t, 1, 0.5, 1)
                    onMoved: v => root.hue = v
                    onFinished: root.copySilently()
                }
                ColorSlider {
                    width: parent.width
                    height: root.cfg.toolIconSize
                    theme: root.theme
                    growMs: root.cfg.fadeOutMs
                    value: root.sat
                    colorAt: t => Qt.hsla(root.hue, t, root.lig, 1)
                    onMoved: v => root.sat = v
                    onFinished: root.copySilently()
                }
                ColorSlider {
                    width: parent.width
                    height: root.cfg.toolIconSize
                    theme: root.theme
                    growMs: root.cfg.fadeOutMs
                    value: root.lig
                    colorAt: t => Qt.hsla(root.hue, root.sat, t, 1)
                    onMoved: v => root.lig = v
                    onFinished: root.copySilently()
                }
            }

            Flow {
                width: parent.width
                spacing: root.gap
                visible: root.actions.recentColors.length > 0
                Repeater {
                    model: root.actions.recentColors
                    Rectangle {
                        id: recent
                        required property var modelData
                        width: root.cfg.toolIconSize
                        height: width
                        radius: width / 4
                        color: modelData.hex
                        border.width: 1
                        border.color: root.theme.cardTrack
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.setRgb(recent.modelData.r, recent.modelData.g, recent.modelData.b);
                                root.copySilently();
                            }
                        }
                    }
                }
            }
        }
    }
}
