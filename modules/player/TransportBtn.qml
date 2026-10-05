import QtQuick

// Play/pause transport button (player module + QS media card): glyph only; the подложка (bg disc) appears
// ONLY while pressed — no idle/hover background.
Item {
    id: btn
    property string glyph: ""
    property real boxSize: 50
    property real glyphSize: 26
    property real glyphScaleY: 1.0
    // Text-swap pop (tempShell StyledText pattern): when `glyph`
    // changes, scale dips to swapFrom on the accel curve, the new glyph
    // swaps in, scale returns on the decel curve. Deliberate exception
    // to the Spring-only rule (user request).
    property bool swapAnimate: false
    property real swapFrom: 0
    property real swapTo: 1
    property int swapDuration: 400
    property bool dimmed: false
    property string iconFamily: "tabler-icons"
    signal clicked

    width: boxSize
    height: boxSize
    opacity: dimmed ? 0.4 : 1

    PressDisc {
        pressed: btnMa.pressed
    }
    Text {
        id: glyphText
        anchors.centerIn: parent
        text: btn.glyph
        color: "#DFE6F2"
        font.family: btn.iconFamily
        font.pixelSize: btn.glyphSize
        transform: Scale {
            yScale: btn.glyphScaleY
            origin.x: glyphText.width / 2
            origin.y: glyphText.height / 2
        }
        Behavior on text {
            enabled: btn.swapAnimate
            SequentialAnimation {
                NumberAnimation {
                    target: glyphText
                    property: "scale"
                    to: btn.swapFrom
                    duration: btn.swapDuration / 3
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0.3, 0, 1, 1, 1, 1]
                }
                PropertyAction {}
                NumberAnimation {
                    target: glyphText
                    property: "scale"
                    to: btn.swapTo
                    duration: btn.swapDuration / 3
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: [0, 0, 0, 1, 1, 1]
                }
            }
        }
    }
    MouseArea {
        id: btnMa
        anchors.fill: parent
        onClicked: if (!btn.dimmed)
            btn.clicked()
    }
}
