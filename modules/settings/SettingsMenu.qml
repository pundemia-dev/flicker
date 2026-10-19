import QtQuick
import "../../components"
import "../../config"

// Pull-down menu of a choice row (iOS context menu): the options with a
// check mark at the current one, right-aligned under the row's value,
// flipped above it near the window bottom. Appears / leaves through the
// blur-fade with a small spring scale; a click outside closes it.
Item {
    id: root
    required property var host
    required property var theme

    property bool shown: false
    property var row: null
    property real anchorRight: 0
    property real anchorTop: 0
    property real anchorBottom: 0

    readonly property real itemHeight: 40
    readonly property var options: root.row ? root.host.optionsOf(root.row) : []
    readonly property var value: root.row ? root.host.valueOf(root.row) : undefined

    function open(row: var, anchor: Item): void {
        const p = anchor.mapToItem(root, anchor.width, 0);
        root.row = row;
        root.anchorRight = p.x + 30;
        root.anchorTop = p.y;
        root.anchorBottom = p.y + anchor.height;
        root.shown = true;
    }

    function label(o: var): string {
        return o.arg !== undefined ? I18n.tr(o.label).arg(o.arg) : I18n.tr(o.label);
    }

    FontMetrics {
        id: metrics
        font.family: root.theme.fontFamily
        font.pixelSize: 15
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.shown
        onPressed: root.shown = false
        // Scrolling the page would leave the menu behind its row.
        onWheel: root.shown = false
    }

    FadeBlur {
        id: panel
        readonly property bool below: root.anchorBottom + 8 + height < root.height - 8
        shown: root.shown
        stiffness: 6
        width: Math.min(320, Math.max(200, Math.ceil(Math.max(0, ...root.options.map(o => metrics.advanceWidth(root.label(o))))) + 64))
        height: Math.min(list.height, root.height - 16)
        x: Math.max(8, Math.min(root.width - width - 8, root.anchorRight - width))
        y: below ? root.anchorBottom + 8 : Math.max(8, root.anchorTop - 8 - height)
        scale: 0.92 + 0.08 * p
        transformOrigin: below ? Item.TopRight : Item.BottomRight

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: root.theme.settingsMenu
            border.width: 1
            border.color: root.theme.settingsSeparator
        }

        Flickable {
            anchors.fill: parent
            contentHeight: list.height
            clip: true

            Column {
                id: list
                width: panel.width
                padding: 6

                Repeater {
                    model: root.options

                    Rectangle {
                        required property var modelData
                        readonly property bool current: modelData.value === root.value
                        width: panel.width - 12
                        height: root.itemHeight
                        radius: 9
                        color: area.containsMouse ? root.theme.settingsPressed : "transparent"

                        Text {
                            visible: parent.current
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: root.theme.islandFg
                            font.family: root.theme.iconFamily
                            font.pixelSize: 17
                        }
                        Text {
                            id: text
                            x: 36
                            width: parent.width - x - 10
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: root.label(modelData)
                            color: root.theme.islandFg
                            font.family: root.theme.fontFamily
                            font.pixelSize: 15
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.host.setValue(root.row, modelData.value);
                                root.shown = false;
                            }
                        }
                    }
                }
            }
        }
    }
}
