import QtQuick
import "../../components"
import "../../components/MorphShape.js" as MorphShape

// Password dots, M3 expressive style (caelestia's lock input, user): every
// typed character pops in as a random shape (MorphDot) that then morphs into
// the round dot; a deleted one shrinks away while the row closes up. A slot
// stays alive until its exit finished (the model trails `count` by
// dotExitMs), so a cleared buffer collapses as a whole, not in one frame.
Item {
    id: root

    required property var cfg
    property int count: 0
    property color color: "white"

    readonly property real dotSize: root.cfg.fieldDotSize ?? 10
    readonly property real shapeSize: root.dotSize * (root.cfg.dotShapeScale ?? 1.7)
    readonly property real slotWidth: root.dotSize + (root.cfg.fieldDotSpacing ?? 10)
    readonly property int maxDots: root.cfg.fieldMaxDots ?? 16

    // Slots as a ListModel, appended / removed at the END only: an int model
    // makes the Repeater rebuild EVERY delegate on change, so all dots
    // replayed their pop-in for each new character.
    ListModel {
        id: slotModel
    }
    onCountChanged: {
        const want = Math.min(root.count, root.maxDots);
        while (slotModel.count < want)
            slotModel.append({});
        trim.restart();
    }
    Timer {
        id: trim
        interval: root.cfg.dotExitMs ?? 450
        onTriggered: {
            const want = Math.min(root.count, root.maxDots);
            while (slotModel.count > want)
                slotModel.remove(slotModel.count - 1);
        }
    }

    implicitWidth: row.width
    implicitHeight: root.shapeSize

    Row {
        id: row
        anchors.centerIn: parent

        Repeater {
            model: slotModel

            Item {
                id: slot
                required property int index
                readonly property bool alive: slot.index < root.count

                property real presence: 0
                Behavior on presence {
                    Spring {
                        stiffness: root.cfg.dotStiffness ?? 5
                        damp: root.cfg.dotDamping ?? 0.42
                        eps: 0.005
                    }
                }
                property real morph: 0
                Behavior on morph {
                    id: morphBehavior
                    Spring {
                        stiffness: root.cfg.dotMorphStiffness ?? 3.5
                        damp: root.cfg.dotMorphDamping ?? 0.55
                        eps: 0.005
                    }
                }
                property string kind: "circle"
                property real turn: 0

                width: root.slotWidth * Math.max(0, slot.presence)
                height: root.shapeSize

                function arrive(): void {
                    slot.kind = MorphShape.RANDOM[Math.floor(Math.random() * MorphShape.RANDOM.length)];
                    slot.turn = Math.random() * Math.PI * 2;
                    morphBehavior.enabled = false;
                    slot.morph = 0;
                    morphBehavior.enabled = true;
                    slot.presence = 1;
                    morphDelay.restart();
                }

                onAliveChanged: {
                    if (slot.alive) {
                        slot.arrive();
                    } else {
                        morphDelay.stop();
                        slot.presence = 0;
                    }
                }
                Component.onCompleted: if (slot.alive)
                    slot.arrive()

                Timer {
                    id: morphDelay
                    interval: root.cfg.dotMorphDelayMs ?? 140
                    onTriggered: slot.morph = 1
                }

                MorphDot {
                    readonly property real s: root.shapeSize + (root.dotSize - root.shapeSize) * Math.max(0, Math.min(1, slot.morph))
                    anchors.centerIn: parent
                    width: s
                    height: s
                    scale: Math.max(0, slot.presence)
                    from: slot.kind
                    to: "circle"
                    t: slot.morph
                    turn: slot.turn
                    color: root.color
                }
            }
        }
    }
}
