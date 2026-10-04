pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// One annotation object (flameshot tool analogue, port of pShell
// tools/AnnotationItem). Rendered twice from the same ListModel row: once
// in the on-screen layer and once in the offscreen physical-resolution
// composite. Children position themselves with absolute editor
// coordinates, so the delegate itself has no geometry.
Item {
    id: root

    required property int index
    required property string type
    required property string colorStr
    required property real thickness
    required property real rx
    required property real ry
    required property real rw
    required property real rh
    required property real px2
    required property real py2
    required property string ptsJson
    required property string textStr
    required property int n
    required property bool editing
    required property real fontPx

    // The fullscreen frozen-grab Image (logical px) sampled by blur/pixelate.
    property Item effectSource: null
    property int pixelateFactor: 8
    property int blurMax: 48
    property real counterDiameter: 18
    property string fontFamily: ""
    // Only the on-screen layer is interactive (text editing grabs focus).
    property bool interactive: false

    signal editCommit(int index, string text)

    readonly property var pts: JSON.parse(ptsJson)

    property bool committed: false
    function commitNow(): void {
        if (root.committed || root.type !== "text" || !root.editing)
            return;
        root.committed = true;
        root.editCommit(root.index, textEditLoader.item ? textEditLoader.item.text : "");
    }

    Loader {
        sourceComponent: {
            switch (root.type) {
            case "rect": return rectC;
            case "ellipse": return ellipseC;
            case "line": return lineC;
            case "arrow": return arrowC;
            case "pencil": return pencilC;
            case "marker": return markerC;
            case "counter": return counterC;
            case "blur": return blurC;
            case "pixelate": return pixelateC;
            default: return null;
            }
        }
    }

    Loader {
        id: textEditLoader
        sourceComponent: root.type === "text" && root.editing ? textEditC : null
    }

    Loader {
        sourceComponent: root.type === "text" && !root.editing ? textShowC : null
    }

    Component {
        id: rectC

        Rectangle {
            x: root.rx
            y: root.ry
            width: root.rw
            height: root.rh
            color: "transparent"
            border.width: root.thickness
            border.color: root.colorStr
        }
    }

    Component {
        id: ellipseC

        Shape {
            x: root.rx
            y: root.ry
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: root.thickness
                strokeColor: root.colorStr
                fillColor: "transparent"

                PathAngleArc {
                    centerX: root.rw / 2
                    centerY: root.rh / 2
                    radiusX: Math.max(1, (root.rw - root.thickness) / 2)
                    radiusY: Math.max(1, (root.rh - root.thickness) / 2)
                    sweepAngle: 360
                }
            }
        }
    }

    Component {
        id: lineC

        Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: root.thickness
                strokeColor: root.colorStr
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: root.rx
                startY: root.ry

                PathLine {
                    x: root.px2
                    y: root.py2
                }
            }
        }
    }

    Component {
        id: markerC

        Shape {
            preferredRendererType: Shape.CurveRenderer
            opacity: 0.45

            ShapePath {
                strokeWidth: root.thickness * 5
                strokeColor: root.colorStr
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                startX: root.rx
                startY: root.ry

                PathLine {
                    x: root.px2
                    y: root.py2
                }
            }
        }
    }

    Component {
        id: arrowC

        Shape {
            id: aShape

            preferredRendererType: Shape.CurveRenderer

            readonly property real adx: root.px2 - root.rx
            readonly property real ady: root.py2 - root.ry
            readonly property real alen: Math.max(1, Math.hypot(adx, ady))
            readonly property real aux: adx / alen
            readonly property real auy: ady / alen
            readonly property real headLen: Math.min(alen, root.thickness * 3 + 8)
            readonly property real headW: (root.thickness * 3 + 8) * 0.5
            readonly property real bx: root.px2 - aux * headLen
            readonly property real by: root.py2 - auy * headLen

            // Shaft, stopped where the head begins.
            ShapePath {
                strokeWidth: root.thickness
                strokeColor: root.colorStr
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: root.rx
                startY: root.ry

                PathLine {
                    x: aShape.bx
                    y: aShape.by
                }
            }

            // Filled head triangle.
            ShapePath {
                strokeWidth: 1
                strokeColor: root.colorStr
                fillColor: root.colorStr
                startX: root.px2
                startY: root.py2

                PathLine {
                    x: aShape.bx - aShape.auy * aShape.headW
                    y: aShape.by + aShape.aux * aShape.headW
                }
                PathLine {
                    x: aShape.bx + aShape.auy * aShape.headW
                    y: aShape.by - aShape.aux * aShape.headW
                }
                PathLine {
                    x: root.px2
                    y: root.py2
                }
            }
        }
    }

    Component {
        id: pencilC

        Shape {
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: root.thickness
                strokeColor: root.colorStr
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathPolyline {
                    path: root.pts.map(p => Qt.point(p.x, p.y))
                }
            }
        }
    }

    Component {
        id: counterC

        Rectangle {
            readonly property real d: root.counterDiameter

            x: root.rx - d / 2
            y: root.ry - d / 2
            width: d
            height: d
            radius: d / 2
            color: root.colorStr

            Text {
                anchors.centerIn: parent
                text: root.n
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: parent.d * 0.55
                font.weight: Font.DemiBold
            }
        }
    }

    Component {
        id: blurC

        Item {
            x: root.rx
            y: root.ry
            width: Math.max(1, root.rw)
            height: Math.max(1, root.rh)
            clip: true

            ShaderEffectSource {
                id: blurSrc

                visible: false
                sourceItem: root.effectSource
                sourceRect: Qt.rect(root.rx, root.ry, Math.max(1, root.rw), Math.max(1, root.rh))
                live: false
                onSourceRectChanged: scheduleUpdate()
                Component.onCompleted: scheduleUpdate()
            }

            MultiEffect {
                anchors.fill: parent
                source: blurSrc
                blurEnabled: true
                blur: 1
                blurMax: root.blurMax
                autoPaddingEnabled: false
            }
        }
    }

    Component {
        id: pixelateC

        ShaderEffectSource {
            x: root.rx
            y: root.ry
            width: Math.max(1, root.rw)
            height: Math.max(1, root.rh)
            sourceItem: root.effectSource
            sourceRect: Qt.rect(root.rx, root.ry, Math.max(1, root.rw), Math.max(1, root.rh))
            textureSize: Qt.size(Math.max(1, Math.round(root.rw / root.pixelateFactor)), Math.max(1, Math.round(root.rh / root.pixelateFactor)))
            smooth: false
            live: false
            onSourceRectChanged: scheduleUpdate()
            onTextureSizeChanged: scheduleUpdate()
            Component.onCompleted: scheduleUpdate()
        }
    }

    Component {
        id: textEditC

        TextEdit {
            x: root.rx
            y: root.ry
            text: root.textStr
            color: root.colorStr
            font.family: root.fontFamily
            font.pixelSize: root.fontPx
            wrapMode: TextEdit.NoWrap
            cursorVisible: true
            selectByMouse: true
            Component.onCompleted: {
                if (root.interactive)
                    forceActiveFocus();
            }
            Keys.onEscapePressed: root.commitNow()
            onActiveFocusChanged: {
                if (!activeFocus && root.interactive)
                    root.commitNow();
            }
        }
    }

    Component {
        id: textShowC

        Text {
            x: root.rx
            y: root.ry
            text: root.textStr
            color: root.colorStr
            font.family: root.fontFamily
            font.pixelSize: root.fontPx
        }
    }
}
