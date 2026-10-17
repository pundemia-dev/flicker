import QtQuick
import Quickshell
import "indicators/glyphs"

// Dev preview of every drawn event glyph (not part of the shell):
//   quickshell -p dev/glyphs/shell.qml
// A grid of tiles at `glyphSize`, each replaying its reveal + loop every
// `replayMs` (click a tile to replay it at once). The symlinked dirs are
// the shell's own; colours stand in for the Theme tokens.
FloatingWindow {
    id: win
    title: "Flicker glyphs"
    implicitWidth: grid.width + 24
    implicitHeight: grid.height + 24 + 140
    color: "#000000"

    readonly property real glyphSize: 64
    readonly property int replayMs: 7000
    readonly property var tones: ({
            blue: "#0A84FF", green: "#59D67A", yellow: "#D8BE52", red: "#E4483E",
            purple: "#8A7CF5", coffee: "#C8915A", orange: "#E58B4D"
        })
    // [glyph, tone, args, label]
    readonly property var items: [
        ["airpods", "blue", {}, "AirPods"],
        ["airpodsMax", "blue", {}, "AirPods Max"],
        ["speaker", "blue", {}, "speaker"],
        ["phone", "blue", {}, "phone"],
        ["tablet", "blue", {}, "tablet"],
        ["laptop", "blue", {}, "laptop"],
        ["watch", "green", {}, "watch"],
        ["mouse", "blue", {}, "mouse"],
        ["keyboard", "blue", {}, "keyboard"],
        ["gamepad", "blue", {}, "gamepad"],
        ["bluetooth", "blue", {}, "bluetooth"],
        ["lock", "green", {}, "VPN"],
        ["moon", "purple", {}, "focus"],
        ["transfer", "blue", {}, "transfer"],
        ["pacman", "yellow", { food: "box" }, "packages"],
        ["error", "red", {}, "error"],
        ["copy", "green", {}, "copied"],
        ["pacman", "yellow", {}, "pacman"],
        ["ghost", "blue", {}, "AUR"],
        ["coffee", "coffee", {}, "caffeine"],
        ["bolt", "green", { mode: "join" }, "plug in"]
    ]

    GlyphRegistry { id: registry }

    // First-run "hello" (wide, not an event glyph).
    Item {
        id: helloTile
        x: 12
        y: grid.y + grid.height + 12
        width: grid.width
        height: 128
        property bool live: true
        Timer {
            running: true
            repeat: true
            interval: win.replayMs
            onTriggered: {
                helloTile.live = false;
                Qt.callLater(() => helloTile.live = true);
            }
        }
        Loader {
            anchors.centerIn: parent
            active: helloTile.live
            sourceComponent: registry.map["hello"]
            onLoaded: {
                item.size = 110;
                item.ready = true;
            }
        }
    }

    Grid {
        id: grid
        x: 12
        y: 12
        columns: 7
        spacing: 6
        Repeater {
            model: win.items
            delegate: Item {
                id: tile
                required property var modelData
                width: 92
                height: 104
                property bool live: true
                function replay(): void {
                    tile.live = false;
                    Qt.callLater(() => tile.live = true);
                }
                Timer {
                    running: true
                    repeat: true
                    interval: win.replayMs
                    onTriggered: tile.replay()
                }
                Loader {
                    x: (parent.width - win.glyphSize) / 2
                    y: 8
                    width: win.glyphSize
                    height: win.glyphSize
                    active: tile.live
                    sourceComponent: registry.map[tile.modelData[0]]
                    onLoaded: {
                        item.size = win.glyphSize;
                        item.color = win.tones[tile.modelData[1]];
                        if ("args" in item)
                            item.args = tile.modelData[2];
                        if ("ready" in item)
                            item.ready = true;
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 80
                    text: tile.modelData[3]
                    color: "#9AA0AA"
                    font.pixelSize: 11
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: tile.replay()
                }
            }
        }
    }
}
