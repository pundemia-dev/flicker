import QtQuick
import "../components"

Item {
    id: root
    property bool showing: true
    property bool blurEnabled: true
    property int blurInMs: 110
    property int fadeInMs: 160
    property int blurOutMs: 110
    property int fadeOutMs: 160
    property int stageDelayMs: 70
    // Change swapKey to replay the blur->fade pattern for an in-place content
    // swap (bar <-> module <-> ticker) without tearing down the container.
    property var swapKey
    // The wash layer must follow the container's corner radius; the old
    // height/2 default turned it into a capsule inside tall module islands.
    property real surfaceRadius: 0
    default property alias content: contentRoot.data
    readonly property real contentOpacity: contentRoot.opacity
    readonly property real blurOpacity: blurLayer.opacity

    onShowingChanged: showing ? inAnim.start() : outAnim.start()
    onSwapKeyChanged: if (showing) swapAnim.restart()

    BlurSurface {
        id: blurLayer
        anchors.fill: parent
        radius: root.surfaceRadius > 0 ? root.surfaceRadius : parent.height / 2
        blurEnabled: root.blurEnabled
        blurStrength: opacity
        opacity: root.showing ? 1 : 0
        visible: opacity > 0.01
        z: -1
    }

    Item {
        id: contentRoot
        anchors.fill: parent
        opacity: root.showing ? 1 : 0
    }

    SequentialAnimation {
        id: inAnim
        NumberAnimation { target: blurLayer; property: "opacity"; to: 1; duration: root.blurInMs }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: contentRoot; property: "opacity"; to: 1; duration: root.fadeInMs }
    }

    SequentialAnimation {
        id: outAnim
        NumberAnimation { target: contentRoot; property: "opacity"; to: 0; duration: root.fadeOutMs }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: blurLayer; property: "opacity"; to: 0; duration: root.blurOutMs }
    }

    // Full two-stage swap: content fades out, blur drops, then blur rises and
    // content fades back in.
    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: contentRoot; property: "opacity"; to: 0; duration: root.fadeOutMs }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: blurLayer; property: "opacity"; to: 0; duration: root.blurOutMs }
        NumberAnimation { target: blurLayer; property: "opacity"; to: 1; duration: root.blurInMs }
        PauseAnimation { duration: root.stageDelayMs }
        NumberAnimation { target: contentRoot; property: "opacity"; to: 1; duration: root.fadeInMs }
    }
}
