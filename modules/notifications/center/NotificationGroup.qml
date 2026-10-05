import QtQuick
import "../../../components"

// One app's notifications in the center, iOS-style. Collapsed: the newest
// tile in front, up to centerStackDepth blank plates peeking out below it
// (each a bit narrower). A tap fans the stack out into a list under a
// header (app name, «Свернуть», ✕ = clear group). All positions are
// springs, so expand/collapse is one continuous fan motion.
Item {
    id: root

    property string app: ""
    property var entries: []
    property bool expanded: false
    property var cfg
    property var theme
    property var frost: null

    signal expandRequested(bool on)
    signal activated(var entry)
    signal dismissGroup
    signal closeRequested

    readonly property int count: root.entries.length
    readonly property bool stacked: root.count > 1 && !root.expanded
    readonly property bool fanned: root.count > 1 && root.expanded
    readonly property real cardH: root.cfg?.centerCardHeight ?? 84
    readonly property real gap: root.cfg?.centerSpacing ?? 8
    readonly property real peek: root.cfg?.centerStackPeek ?? 9
    readonly property int depth: root.cfg?.centerStackDepth ?? 2
    readonly property real headerH: 34

    // Target (not animated) height: the center sums these for the island size.
    readonly property real targetHeight: root.fanned
        ? root.headerH + root.count * root.cardH + (root.count - 1) * root.gap
        : root.cardH + Math.min(root.count - 1, root.depth) * root.peek

    height: root.targetHeight
    Behavior on height { Spring {} }

    // ── Header (expanded group only) ──
    Item {
        width: parent.width
        height: root.headerH - 6
        opacity: root.fanned ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: root.app
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: "#F0F4FB"
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Pill {
                frost: root.frost
                label: "Свернуть"
                onClicked: root.expandRequested(false)
            }
            Pill {
                frost: root.frost
                label: "✕"
                onClicked: root.dismissGroup()
            }
        }
    }

    Repeater {
        id: cardRepeater
        model: root.entries

        SwipeCard {
            id: card
            required property var modelData
            required property int index

            readonly property int level: Math.min(card.index, root.depth)

            width: root.width
            height: root.cardH
            z: root.count - card.index
            entry: card.modelData
            cfg: root.cfg
            theme: root.theme
            frost: root.frost
            // Translucent plates must not show through the tile above: the
            // part covered by the previous card (live, scaled geometry) is
            // cut from this one's surface. 0 once the stack fans out.
            coverTop: {
                if (card.index === 0 || cardRepeater.count < 0)
                    return 0;
                const prev = cardRepeater.itemAt(card.index - 1);
                if (!prev || card.scale <= 0)
                    return 0;
                // Bottom-anchored scale: visual top = y + h(1 - s), bottom = y + h.
                const covered = prev.y + prev.height - (card.y + card.height * (1 - card.scale));
                return Math.max(0, Math.min(card.height, covered / card.scale));
            }
            // Bottom-anchored scale: a plate's bottom edge stays at y + h,
            // so exactly `peek` px of each layer shows below the one above.
            transformOrigin: Item.Bottom
            y: root.fanned ? root.headerH + card.index * (root.cardH + root.gap)
                : card.level * root.peek
            scale: root.fanned ? 1 : 1 - 0.05 * card.level
            opacity: root.fanned || card.index <= root.depth ? 1 : 0
            plateLevel: root.fanned ? 0 : card.level
            showContent: root.fanned || card.index === 0
            interactive: root.fanned || card.index === 0
            groupCount: root.stacked && card.index === 0 ? root.count : 0

            // Same spring as the island body and the group height (Spring
            // defaults): mismatched curves made the fan-out run in two
            // phases (cards ahead of / behind the growing island).
            Behavior on y { Spring {} }
            Behavior on scale { Spring { eps: 0.001 } }
            Behavior on opacity { Spring { stiffness: 6; damp: 0.6; eps: 0.01 } }

            onTapped: {
                if (root.stacked)
                    root.expandRequested(true);
                else
                    root.activated(card.modelData);
            }
            // iOS: swiping a collapsed stack clears the whole stack.
            onDismissRequested: {
                if (root.stacked)
                    root.dismissGroup();
                else
                    card.modelData.dismiss();
            }
            onCloseRequested: root.closeRequested()
        }
    }
}
