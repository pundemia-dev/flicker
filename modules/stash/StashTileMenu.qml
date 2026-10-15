import QtQuick
import Quickshell
import "../../components"
import "../../config"

// Action panel of a tray file (the tile's menu button grown through the
// tray's DropExpand): file name on top, a row of glyph buttons with labels.
// Every action runs after the drop has landed back on the button
// (expander.close(fn)) — delete removes the tile it flies home to.
Item {
    id: root
    property var expander: null
    // The StashTile (live state: favourite, transcript, file).
    property var payload: null
    readonly property var tile: root.payload
    readonly property var cfg: root.tile?.cfg ?? null
    readonly property var mc: root.cfg?.menu ?? ({})
    readonly property var theme: root.tile?.theme ?? null

    readonly property var actions: {
        const t = root.tile;
        if (!t)
            return [];
        const out = [{ key: "open", glyph: "", label: I18n.tr("Open") }];
        if (t.localSend?.enabled)
            out.push({ key: "send", glyph: "", label: I18n.tr("Send"), accent: true });
        out.push({ key: "fav", glyph: "", label: t.isFav ? I18n.tr("Unpin") : I18n.tr("Pin"), checked: t.isFav });
        if (t.canTranscribe)
            out.push({ key: "transcribe", glyph: "", label: I18n.tr("Transcript"), checked: t.trState === "done" });
        out.push({ key: "delete", glyph: "", label: I18n.tr("Delete"), danger: true });
        return out;
    }

    function run(key: string): void {
        const t = root.tile;
        root.expander?.close(() => {
            switch (key) {
            case "open":
                Quickshell.execDetached(["xdg-open", t.filePath]);
                break;
            case "send":
                t.sendRequested([t.filePath]);
                break;
            case "fav":
                t.stash.toggleFav(t.index);
                break;
            case "transcribe":
                t.transcribeRequested(t.filePath);
                break;
            case "delete":
                t.stash.remove(t.filePath);
                break;
            }
        });
    }

    Text {
        id: name
        x: root.mc.padding ?? 12
        y: root.mc.padding ?? 12
        width: root.width - 2 * x
        text: root.tile?.fileName ?? ""
        color: root.theme?.subtleFg ?? "#99EBEBF5"
        font.pixelSize: root.mc.nameSize ?? 12
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignHCenter
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.mc.padding ?? 12
        spacing: root.mc.spacing ?? 4

        Repeater {
            model: root.actions
            delegate: Item {
                id: cell
                required property var modelData
                width: root.mc.cellWidth ?? 54
                height: disc.height + 4 + label.implicitHeight

                Rectangle {
                    id: disc
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: root.mc.buttonSize ?? 40
                    height: width
                    radius: width / 2
                    readonly property color base: cell.modelData.danger ? (root.theme?.accentRed ?? "#E4483E")
                        : cell.modelData.accent ? (root.theme?.cardBlue ?? "#0F7CEC")
                        : cell.modelData.checked ? Qt.alpha(root.theme?.cardBlue ?? "#0F7CEC", 0.55)
                        : (root.theme?.cardTrack ?? "#2C2C2E")
                    color: ma.containsMouse ? Qt.lighter(base, 1.2) : base
                    scale: ma.pressed ? 0.9 : 1
                    Behavior on scale { Spring { stiffness: 6; damp: 0.45; eps: 0.002 } }
                    Icon {
                        anchors.centerIn: parent
                        text: cell.modelData.glyph
                        font.family: root.theme?.iconFamily ?? "tabler-icons"
                        iconSize: Math.round(disc.width * 0.5)
                        iconColor: root.theme?.islandFg ?? "#FFFFFF"
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.run(cell.modelData.key)
                    }
                }
                Text {
                    id: label
                    anchors.top: disc.bottom
                    anchors.topMargin: 4
                    width: parent.width
                    text: cell.modelData.label
                    color: root.theme?.islandFg ?? "#FFFFFF"
                    font.pixelSize: root.mc.labelSize ?? 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }
}
