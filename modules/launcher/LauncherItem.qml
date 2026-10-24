import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../components"
import "calc"
import "LauncherMetrics.js" as Metrics

// One list row (pShell UniversalDelegate port), entry format documented in
// api/LauncherPlugin.qml. The selection plate lives in LauncherList (it
// slides between rows); a row only lightens on hover. Image rows
// (backgroundImage) are double height with the text over a bottom scrim.
// `appear` 0..1 is driven by the list's add/remove transitions: the row
// fades in out of a blur (ContentSwap look) and dissolves into one.
// `entry.live` (an object with the same fields) is read instead of the
// entry for the visible text, so a row can change in place (calculator);
// `entry.calcCard` draws the calculator's result card.
Item {
    id: root
    required property var modelData
    required property int index
    required property var theme
    required property var cfg
    required property bool current
    signal hovered

    readonly property var entry: root.modelData
    readonly property var view: root.entry?.live ?? root.entry
    readonly property bool isCard: !!root.entry?.calcCard
    readonly property bool hasImage: !!root.entry?.backgroundImage
    readonly property real rowRadius: root.cfg.itemRadius

    height: Metrics.itemHeight(root.cfg, root.entry)

    // Set by the view's add/remove transitions (LauncherList).
    property bool entering: false
    // Added by the scroll window growing (not a new result): no fade-in.
    property bool quietAdd: false
    property bool leaving: false
    property real appear: 1
    Behavior on appear {
        id: appearAnim
        Spring {
            stiffness: root.leaving ? root.cfg.removeStiffness : root.cfg.appearStiffness
            damp: root.leaving ? root.cfg.removeDamping : root.cfg.appearDamping
            eps: 0.005
        }
    }
    onEnteringChanged: if (root.entering && root.quietAdd) {
        root.entering = false;
    } else if (root.entering) {
        appearAnim.enabled = false;
        root.appear = 0;
        appearAnim.enabled = true;
        root.appear = 1;
        root.entering = false;
    }
    onLeavingChanged: if (root.leaving) root.appear = 0
    opacity: root.appear

    // FLIP slide: the ListView places a moved/displaced row at its new slot
    // at once; the row offsets itself back to where it was and springs the
    // offset to 0. (A SpringAnimation in the view's move/displaced
    // transitions does not pick up the implicit target y — moved rows got
    // stuck in their old slot.) First placement does not slide.
    property real lastY: NaN
    property real shift: 0
    Behavior on shift {
        id: shiftAnim
        Spring { stiffness: root.cfg.motionStiffness; damp: root.cfg.motionDamping; eps: 0.25 }
    }
    transform: Translate { y: root.shift + root.scrollShift }

    // Scroll on springs (LauncherList.scrollTo moves contentY at once): the
    // row offsets itself back by the step and springs to 0; `distance` =
    // rows from the selection, softer farther away (`scrollStagger`).
    property real scrollShift: 0
    Behavior on scrollShift {
        id: scrollAnim
        Spring {
            id: scrollSpring
            stiffness: root.cfg.scrollStiffness ?? 3
            damp: root.cfg.scrollDamping ?? 0.5
            eps: 0.25
        }
    }
    function kickScroll(d: real, distance: real): void {
        scrollSpring.stiffness = (root.cfg.scrollStiffness ?? 3) / (1 + (root.cfg.scrollStagger ?? 0) * distance);
        scrollAnim.enabled = false;
        root.scrollShift += d;
        scrollAnim.enabled = true;
        root.scrollShift = 0;
    }
    onYChanged: {
        if (!isNaN(root.lastY) && root.lastY !== root.y) {
            shiftAnim.enabled = false;
            root.shift += root.lastY - root.y;
            shiftAnim.enabled = true;
            root.shift = 0;
        }
        root.lastY = root.y;
    }

    function trigger(): void {
        if (typeof root.entry?.onClicked === "function")
            root.entry.onClicked();
    }

    function triggerAlt(): void {
        if (typeof root.entry?.onAltClicked === "function")
            root.entry.onAltClicked();
        else
            trigger();
    }

    Rectangle {
        anchors.fill: parent
        radius: root.rowRadius
        color: root.theme.cardBg
        opacity: !root.current && ma.containsMouse ? 0.5 : 0
        Behavior on opacity { Spring { eps: 0.01 } }
    }

    BlurSurface {
        anchors.fill: parent
        amount: root.appear < 0.999 ? 1 - root.appear : 0
        blurMax: root.cfg.rowBlurMax

        Loader {
            anchors.fill: parent
            active: root.hasImage
            sourceComponent: RoundedImage {
                source: root.entry?.backgroundImage ?? ""
                radius: root.rowRadius
                fallbackColor: root.theme.cardBg
                opacity: root.current ? 1 : 0.75
                Behavior on opacity { Spring { eps: 0.01 } }

                Rectangle {
                    anchors.fill: parent
                    radius: root.rowRadius
                    gradient: Gradient {
                        GradientStop { position: 0.3; color: "transparent" }
                        GradientStop { position: 1.0; color: "#C0000000" }
                    }
                }
            }
        }

        Loader {
            anchors.fill: parent
            anchors.leftMargin: root.cfg.itemPadding * 1.5
            anchors.rightMargin: root.cfg.itemPadding * 1.5
            active: root.isCard
            sourceComponent: CalcCard {
                slot: root.view
                theme: root.theme
                cfg: root.cfg
            }
        }

        Item {
            id: content
            visible: !root.isCard
            opacity: root.view?.stale ? 0.45 : 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: root.cfg.itemPadding
            anchors.rightMargin: root.cfg.itemPadding
            height: root.cfg.itemHeight

            // Left: swatch | app icon | glyph on a disc.
            Item {
                id: leftBox
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool used: !root.hasImage && (!!root.view?.leftIcon || !!root.view?.swatchColor)
                width: used ? root.cfg.iconBox : 0
                height: root.cfg.iconBox

                Rectangle {
                    visible: leftBox.used && !!root.view?.swatchColor
                    anchors.centerIn: parent
                    width: parent.height * 0.8
                    height: width
                    radius: width * 0.3
                    color: root.view?.swatchColor ?? "transparent"
                    border.width: 1
                    border.color: "#33FFFFFF"
                }
                IconImage {
                    visible: leftBox.used && !root.view?.swatchColor && !!root.view?.isLeftIconImage
                    anchors.fill: parent
                    asynchronous: true
                    source: visible ? Quickshell.iconPath(root.view.leftIcon, "application-x-executable") : ""
                }
                Rectangle {
                    visible: leftBox.used && !root.view?.swatchColor && !root.view?.isLeftIconImage
                    anchors.fill: parent
                    radius: height / 2
                    color: root.theme.qsDisc

                    Text {
                        anchors.centerIn: parent
                        text: root.view?.leftIcon ?? ""
                        font.family: root.theme.iconFamily
                        font.pixelSize: root.cfg.iconSize
                        color: root.theme.islandFg
                    }
                }
            }

            Column {
                anchors.left: leftBox.right
                anchors.leftMargin: leftBox.used ? root.cfg.itemPadding : 0
                anchors.right: rightLabel.left
                anchors.rightMargin: rightLabel.text ? root.cfg.itemPadding : 0
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: root.view?.header ?? ""
                    font.pixelSize: root.cfg.fontSize
                    font.weight: Font.DemiBold
                    color: root.theme.islandFg
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.view?.text ?? ""
                    font.pixelSize: root.cfg.subFontSize
                    color: root.theme.cardDim
                    elide: Text.ElideRight
                }
            }

            Text {
                id: rightLabel
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.view?.rightText ?? ""
                font.pixelSize: root.cfg.subFontSize
                color: root.theme.cardDim
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        // A row on its way out takes no input.
        enabled: root.appear > 0.5
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered()
        onClicked: mouse => {
            if (mouse.modifiers & Qt.AltModifier)
                root.triggerAlt();
            else
                root.trigger();
        }
    }
}
