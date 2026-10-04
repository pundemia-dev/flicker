import QtQuick

// Offscreen physical-resolution composite for export (port of pShell's
// RegionEditor composite): the grab at 1:1 pixels, cropped to the
// selection, with the annotations scaled by the output scale on top.
// Lives off to the left so it never shows; grabToImage renders it.
Item {
    id: root
    required property var editor
    required property Item effectSource

    readonly property var ed: root.editor
    visible: root.ed.hasSelection
    x: -width - 4000
    y: 0
    width: Math.max(1, Math.round(root.ed.selW * root.ed.dpr))
    height: Math.max(1, Math.round(root.ed.selH * root.ed.dpr))

    Image {
        x: -Math.round(root.ed.selX * root.ed.dpr)
        y: -Math.round(root.ed.selY * root.ed.dpr)
        width: root.ed.physW
        height: root.ed.physH
        source: root.ed.srcUrl
        smooth: false
    }

    Item {
        x: -Math.round(root.ed.selX * root.ed.dpr)
        y: -Math.round(root.ed.selY * root.ed.dpr)
        transform: Scale {
            xScale: root.ed.dpr
            yScale: root.ed.dpr
        }

        Repeater {
            model: root.ed.model.objects

            AnnotationItem {
                effectSource: root.effectSource
                pixelateFactor: root.ed.cfg.pixelateFactor
                blurMax: root.ed.cfg.effectBlurMax
                counterDiameter: root.ed.model.counterDiameter(thickness)
                fontFamily: root.ed.theme.fontFamily
            }
        }
    }
}
