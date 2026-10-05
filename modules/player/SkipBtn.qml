import QtQuick
import QtQuick.Shapes
import "../../components"

// Skip prev/next button built from shapes instead of an icon-font glyph:
// two rounded triangles pointing the motion way (zero gap) inside a
// two-triangle-wide track, plus a third triangle staged hidden (scale 0)
// at the rear slot. Press choreography runs on ONE spring driver
// (track.p 0 -> 1): the extreme front triangle fades and drives away,
// the staged one scales up from the rear edge, and the remaining
// triangle is pushed out by it — its x is bound to the staged
// triangle's scale, so the scale spring shapes its travel as well. When
// the spring lands, the roles rotate (front -> staged, staged -> rear,
// rear -> front) and p resets to 0 within the same frame, so nothing
// visibly snaps. Rapid re-presses mid-flight are ignored.
Item {
    id: skip
    property int direction: 1 // 1 = next (point right), -1 = prev (point left)
    property real boxSize: 50
    property real triSize: 22 // triangle height, ex-glyph size
    property bool dimmed: false
    signal clicked

    readonly property real triW: skip.triSize * 0.95
    readonly property real triCorner: skip.triSize * 0.12

    width: skip.boxSize
    height: skip.boxSize
    opacity: skip.dimmed ? 0.4 : 1

    function go(): void {
        if (skip.dimmed || fly.running)
            return;
        skip.clicked();
        fly.restart();
    }

    PressDisc {
        pressed: skipMa.pressed
    }

    Item {
        id: track
        property real p: 0
        property int iIn: 2
        property int iRear: 0
        property int iFront: 1

        readonly property real rearSlot: skip.direction > 0 ? 0 : skip.triW
        readonly property real frontSlot: skip.direction > 0 ? skip.triW : 0

        function posFor(idx: int): real {
            const push = frontSlot - rearSlot;
            if (idx === iRear)
                return rearSlot + push * p;
            if (idx === iFront)
                return frontSlot + push * 0.55 * p;
            return rearSlot;
        }
        function finishSwap(): void {
            const f = iFront;
            iFront = iRear;
            iRear = iIn;
            iIn = f;
            p = 0;
        }

        width: skip.triW * 2
        height: skip.triSize
        anchors.centerIn: parent

        Spring {
            id: fly
            target: track
            property: "p"
            to: 1
            stiffness: 5
            damp: 0.5
            eps: 0.001
            onFinished: track.finishSwap()
        }

        Shape {
            property int idx: 0
            width: skip.triW
            height: skip.triSize
            transformOrigin: skip.direction > 0 ? Item.Left : Item.Right
            scale: idx === track.iIn ? track.p : 1
            x: track.posFor(idx)
            opacity: idx === track.iFront ? 1 - track.p : 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#DFE6F2"
                strokeColor: "#DFE6F2"
                strokeWidth: skip.triCorner * 2
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathMove {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triCorner
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triSize - skip.triCorner
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triW - skip.triCorner : skip.triCorner
                    y: skip.triSize / 2
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triCorner
                }
            }
        }
        Shape {
            property int idx: 1
            width: skip.triW
            height: skip.triSize
            transformOrigin: skip.direction > 0 ? Item.Left : Item.Right
            scale: idx === track.iIn ? track.p : 1
            x: track.posFor(idx)
            opacity: idx === track.iFront ? 1 - track.p : 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#DFE6F2"
                strokeColor: "#DFE6F2"
                strokeWidth: skip.triCorner * 2
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathMove {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triCorner
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triSize - skip.triCorner
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triW - skip.triCorner : skip.triCorner
                    y: skip.triSize / 2
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triCorner
                }
            }
        }
        Shape {
            property int idx: 2
            width: skip.triW
            height: skip.triSize
            transformOrigin: skip.direction > 0 ? Item.Left : Item.Right
            scale: idx === track.iIn ? track.p : 1
            x: track.posFor(idx)
            opacity: idx === track.iFront ? 1 - track.p : 1
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "#DFE6F2"
                strokeColor: "#DFE6F2"
                strokeWidth: skip.triCorner * 2
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathMove {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triCorner
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triSize - skip.triCorner
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triW - skip.triCorner : skip.triCorner
                    y: skip.triSize / 2
                }
                PathLine {
                    x: skip.direction > 0 ? skip.triCorner : skip.triW - skip.triCorner
                    y: skip.triCorner
                }
            }
        }
    }

    MouseArea {
        id: skipMa
        anchors.fill: parent
        onClicked: skip.go()
    }
}
