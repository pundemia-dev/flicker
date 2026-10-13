import QtQuick
import "../../components"

// Shazam (services/Shazam): the tabler brand-shazam glyph. Appears by
// springing up from `appearScale`; while `args.listening` it breathes
// (timed loop between 1 and `breathScale`, `breathMs` per half — the iOS
// listening pulse) and fades to `breathOpacity` at the low point; when the
// listening ends (in-place event update) it settles on a spring and a
// match (`args.found`) pops once (GlyphBump curve).
GlyphBase {
    id: root
    glyphName: "shazam"

    readonly property bool listening: !!root.args?.listening
    readonly property bool found: !!root.args?.found
    property real appear: 0
    property real breath: 0
    Behavior on appear { Spring { stiffness: root.p("appearStiffness", 4); damp: root.p("appearDamping", 0.35); eps: 0.005 } }

    onBegin: {
        root.appear = 1;
        if (root.listening)
            breathLoop.start();
        else if (root.found)
            bump.bump();
    }
    onListeningChanged: {
        if (!root.begun)
            return;
        if (root.listening) {
            breathLoop.start();
            return;
        }
        breathLoop.stop();
        settle.start();
        if (root.found)
            bump.bump();
    }

    SequentialAnimation {
        id: breathLoop
        loops: Animation.Infinite
        NumberAnimation {
            target: root
            property: "breath"
            to: 1
            duration: root.p("breathMs", 650)
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: root
            property: "breath"
            to: 0
            duration: root.p("breathMs", 650)
            easing.type: Easing.InOutSine
        }
    }
    NumberAnimation {
        id: settle
        target: root
        property: "breath"
        to: 0
        duration: root.p("breathMs", 650) / 2
        easing.type: Easing.OutCubic
    }
    GlyphBump {
        id: bump
    }

    Icon {
        anchors.centerIn: parent
        text: ""
        font.family: root.theme?.iconFamily ?? "tabler-icons"
        iconSize: root.size
        iconColor: root.color
        opacity: Math.max(0, Math.min(1, root.appear)) * (1 - root.breath * (1 - root.p("breathOpacity", 0.55)))
        scale: (root.p("appearScale", 0.5) + (1 - root.p("appearScale", 0.5)) * root.appear)
            * (1 - root.breath * (1 - root.p("breathScale", 0.8))) * bump.value
    }
}
